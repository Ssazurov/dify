#!/usr/bin/env python3
"""
shard_tables.py — интейк-препроцессор RAG=GAR (Docling → sharded markdown).

Проблема, которую решает: документ "Solar_SafeInspect_2.4.10_Release_Notes_sharded.md"
был сделан вручную/программно один раз — при обычной загрузке через Dify UI
такого шардирования таблиц не происходит, поэтому Код-нода (Вариант C) не находит
теги [TABLE: slug | row N/M] и докомплектация больших таблиц не работает.

Что делает скрипт:
  1. Парсит вход (docx/pdf/pptx/html/md/xlsx — всё, что понимает Docling).
  2. Для каждой таблицы находит ближайший предшествующий заголовок → генерит slug
     (тот же паттерн, что и в эталонном документе: "<slug_заголовка>_<номер_таблицы>").
  3. Разбивает таблицу на строки, каждая строка — отдельный markdown-блок вида
        [TABLE: <slug> | row NN/MM]
        Заголовок1: значение1; Заголовок2: значение2; ...
     разделённый пустой строкой от соседних блоков — это то, что Dify нарежет
     на отдельные child-чанки при child_delimiter="\n\n" (уже настроено в KB).
  4. Опционально сохраняет исходную таблицу как markdown ПЕРЕД шардированными
     строками — для читаемости в ответах LLM (см. --keep-original-table).
  5. Добавляет шапку метаданных в формате, который уже парсится вашей схемой
     (doc_metadata: doc_name, doc_type, product_version, doc_approved, doc_link_orig)
     + новые поля version_major / is_latest / product для версионности.
  6. (опционально, --upload) Заливает результат в Dify KB через Dataset API
     с process_rule, идентичным вашей рабочей настройке (parent \n#, child \n\n,
     child_max_chunk_length=512, max_chunk_length=4000/2000 — проверьте актуальные
     значения перед боевым прогоном, я взял их из вашего прогресса).

ВАЖНО — что НЕ проверено (нет доступа к вашей среде/файлам для теста):
  - Точный API docling-core под вашей установленной версией (TableItem.export_to_dataframe
    сигнатура менялась между релизами — есть fallback на ручной разбор .data.grid).
  - Формат nearest_heading — эвристика "последний SectionHeaderItem перед таблицей
    в document-order"; для документов с таблицами без заголовка над ними даст
    generic slug "table_N" — проверьте на вашем реальном Release Notes / What's New.
  - Эндпоинт для записи doc_metadata через API — в 1.15.0 это Knowledge Base
    metadata management (/v1/datasets/{id}/metadata + /documents/{doc_id}/metadata-values),
    сверьте с актуальной OpenAPI-схемой вашего форка, я не проверял это точно.

Прогоните на ОДНОМ реальном документе руками (без --upload), откройте результат
и сверьте с sharded.md построчно, прежде чем автоматизировать всю папку.
"""

import argparse
import json
import re
import sys
from pathlib import Path
import os, time, torch
from huggingface_hub import login



def slugify(text: str, max_words: int = 6) -> str:
    text = (text or "").lower().strip()
    text = re.sub(r"[^\w\s]", "", text, flags=re.UNICODE)
    words = text.split()[:max_words]
    slug = "_".join(words)
    slug = re.sub(r"_+", "_", slug).strip("_")
    return slug or "table"


def get_table_dataframe(table_item, doc):
    """Возвращает (headers, rows) как списки строк. Пробует API docling-core,
    падает на ручной разбор .data.grid если сигнатура другая."""
    try:
        df = table_item.export_to_dataframe(doc)
        headers = [str(c) for c in df.columns]
        rows = [[str(v) for v in row] for row in df.itertuples(index=False)]
        return headers, rows
    except TypeError:
        try:
            df = table_item.export_to_dataframe()
            headers = [str(c) for c in df.columns]
            rows = [[str(v) for v in row] for row in df.itertuples(index=False)]
            return headers, rows
        except Exception:
            pass
    except Exception:
        pass

    # fallback: ручной разбор grid из TableData
    grid = getattr(table_item.data, "grid", None)
    if not grid or len(grid) < 2:
        return [], []
    headers = [getattr(c, "text", str(c)).strip() for c in grid[0]]
    rows = [[getattr(c, "text", str(c)).strip() for c in r] for r in grid[1:]]
    return headers, rows


def flatten_table(headers, rows, slug: str) -> list[str]:
    total = len(rows)
    blocks = []
    width = len(str(total))
    for i, row in enumerate(rows, start=1):
        pairs = []
        for h, val in zip(headers, row):
            h, val = (h or "").strip(), (val or "").strip()
            if h and val and val.lower() != "nan":
                pairs.append(f"{h}: {val}")
        if not pairs:
            continue
        line = "; ".join(pairs)
        blocks.append(f"[TABLE: {slug} | row {i:0{width}d}/{total:0{width}d}]\n{line}")
    return blocks


def render_original_table_md(headers, rows) -> str:
    if not headers:
        return ""
    out = ["| " + " | ".join(headers) + " |", "|" + "---|" * len(headers)]
    for row in rows:
        out.append("| " + " | ".join(row) + " |")
    return "\n".join(out)


def build_metadata_header(a) -> str:
    version_major = a.version.split(".")[0] if a.version else ""
    return (
        f"[doc_name] {a.doc_name}\n"
        f"[product] {a.product}\n"
        f"[doc_type] {a.doc_type}\n"
        f"[version] {a.version}\n"
        f"[version_major] {version_major}\n"
        f"[is_latest] {str(a.is_latest).lower()}\n"
        f"[source_file] {Path(a.input).name}\n"
    )


def convert(a):
    from docling.document_converter import DocumentConverter
    from docling_core.types.doc import TableItem, TextItem
    from docling.datamodel.pipeline_options import PipelineOptions, TableStructureOptions
    import time

    print("⏳ Настройка пайплайна...")
    pipeline_opts = PipelineOptions(
        do_ocr=False,
        do_table_structure=True,
        table_structure_options=TableStructureOptions(device=a.device),
        do_image_analysis=False,       # отключает детекцию изображений (ускоряет)
        do_code_enrichment=True      # если не нужно извлекать код
    )

    converter = DocumentConverter()
    converter.progress_bar = True
    converter.pipeline_options = pipeline_opts

    print(f"🔄 Начинаю конвертацию файла: {a.input}")
    start_time = time.time()

    result = converter.convert(a.input)

    elapsed = time.time() - start_time
    print(f"✅ Конвертация завершена за {elapsed:.1f} сек. Обрабатываю результат...")

    doc = result.document
    print(f"📄 Документ: {len(list(doc.iterate_items()))} элементов")

    table_counter = 0
    out_lines = [build_metadata_header(a), f"\n# {a.doc_name}\n"]
    pending_heading = ""

    for idx, (item, _level) in enumerate(doc.iterate_items()):
        if idx % 50 == 0:
            print(f"   Обработано {idx} элементов...")

        if isinstance(item, TableItem):
            table_counter += 1
            heading = pending_heading or f"table"
            slug = f"{slugify(heading)}_{table_counter}"
            headers, rows = get_table_dataframe(item, doc)
            if not rows:
                print(f"⚠️  Таблица {table_counter} ('{heading}') — пуста, пропущена")
                continue
            out_lines.append(f"\n### {heading}\n")
            if a.keep_original_table:
                out_lines.append(render_original_table_md(headers, rows))
            out_lines.extend(flatten_table(headers, rows, slug))
        elif isinstance(item, TextItem):
            label = getattr(item, "label", "")
            text = (item.text or "").strip()
            if not text:
                continue
            if label in ("section_header", "title"):
                pending_heading = text
                out_lines.append(f"\n## {text}\n")
            else:
                out_lines.append(text)

    Path(a.output).write_text("\n\n".join(out_lines), encoding="utf-8")
    print(f"✅ Готово: {table_counter} таблиц шардировано → {a.output}")

def upload_to_dify(a):
    """Best-effort: заливка через Dataset API. Сверьте process_rule и metadata
    endpoint с текущей OpenAPI-схемой вашего форка (1.15.0) перед использованием —
    не проверено на вашей установке."""
    import requests

    with open(a.output, "rb") as f:
        files = {"file": (Path(a.output).name, f, "text/markdown")}
        data = {
            "data": json.dumps({
                "indexing_technique": "high_quality",
                "process_rule": {
                    "mode": "custom",
                    "rules": {
                        "pre_processing_rules": [
                            {"id": "remove_extra_spaces", "enabled": True},
                            {"id": "remove_urls_emails", "enabled": False},
                        ],
                        "segmentation": {
                            "separator": "\n#",
                            "max_tokens": 4000,
                        },
                        "parent_mode": "paragraph",
                        "subchunk_segmentation": {
                            "separator": "\n\n",
                            "max_tokens": 512,
                        },
                    },
                },
            })
        }
        headers = {"Authorization": f"Bearer {a.dataset_api_key}"}
        url = f"{a.dify_base_url}/v1/datasets/{a.dataset_id}/document/create-by-file"
        resp = requests.post(url, headers=headers, files=files, data=data, timeout=60)
    print(resp.status_code, resp.text[:2000])
    resp.raise_for_status()
    return resp.json()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="путь к исходному файлу (docx/pdf/pptx/html/md/xlsx)")
    ap.add_argument("output", help="путь к выходному .md")
    ap.add_argument("--doc-name", required=True)
    ap.add_argument("--product", required=True)
    ap.add_argument("--doc-type", required=True, help="release_notes | whats_new | manual | ...")
    ap.add_argument("--version", default="")
    ap.add_argument("--is-latest", default="true")
    ap.add_argument("--keep-original-table", action="store_true",
                     help="дублировать исходную markdown-таблицу перед шардированными строками (для читаемости в LLM-ответах)")
    ap.add_argument("--upload", action="store_true", help="залить результат в Dify KB через Dataset API")
    ap.add_argument("--dify-base-url", default="http://localhost")
    ap.add_argument("--dataset-id", default="")
    ap.add_argument("--dataset-api-key", default="")
    ap.add_argument("--device", default="cpu", choices=["cpu", "cuda"],
                help="устройство для инференса (cpu/cuda)")
                
    a = ap.parse_args()

    convert(a)

    if a.upload:
        if not (a.dataset_id and a.dataset_api_key):
            print("ERROR: --upload требует --dataset-id и --dataset-api-key", file=sys.stderr)
            sys.exit(1)
        upload_to_dify(a)


if __name__ == "__main__":
    main()
