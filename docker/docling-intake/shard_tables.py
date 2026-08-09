#!/usr/bin/env python3
"""
shard_tables.py — интейк-препроцессор RAG=GAR (Docling → sharded markdown).
Доработки:
- Умный slug из иерархии заголовков
- Исключение оглавлений из шардирования
- Добавление номера страницы в блоки строк
- Удаление дублирования заголовков
"""

import argparse
import json
import os
import re
import sys
import time
import subprocess as _subprocess

if os.getenv("DEBUG_TRACE_TESSERACT"):
    _orig_popen = _subprocess.Popen

    def _traced_popen(cmd, *a, **kw):
        try:
            print("TESSERACT_CMD_TRACE:", cmd, file=sys.stderr, flush=True)
        except Exception:
            pass
        return _orig_popen(cmd, *a, **kw)

    _subprocess.Popen = _traced_popen
from pathlib import Path

import torch
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

    grid = getattr(table_item.data, "grid", None)
    if not grid or len(grid) < 2:
        return [], []
    headers = [getattr(c, "text", str(c)).strip() for c in grid[0]]
    rows = [[getattr(c, "text", str(c)).strip() for c in r] for r in grid[1:]]
    return headers, rows


def flatten_table(headers, rows, slug: str, page: int = None) -> list[str]:
    """Генерирует блоки строк таблицы с тегами и номером страницы (если указан)."""
    total = len(rows)
    blocks = []
    width = len(str(total))
    page_suffix = f" | page {page}" if page is not None else ""
    for i, row in enumerate(rows, start=1):
        pairs = []
        for h, val in zip(headers, row):
            h, val = (h or "").strip(), (val or "").strip()
            if h and val and val.lower() != "nan":
                pairs.append(f"{h}: {val}")
        if not pairs:
            continue
        line = "; ".join(pairs)
        blocks.append(f"[TABLE: {slug} | row {i:0{width}d}/{total:0{width}d}{page_suffix}]\n{line}")
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
        f"[doc_name]: {a.doc_name}\n"
        f"[product]: {a.product}\n"
        f"[doc_type]: {a.doc_type}\n"
        f"[version]: {a.version}\n"
        f"[version_major]: {version_major}\n"
        f"[is_latest]: {str(a.is_latest).lower()}\n"
        f"[source_file]: {Path(a.input).name}\n"
    )


def is_toc_table(headers, rows, threshold=0.7):
    if not rows or len(rows) < 3:
        return False

    if len(headers) == 2:
        num_col = 1
        num_count = 0
        for r in rows:
            if len(r) > num_col:
                val = r[num_col].strip()
                if re.match(r'^[\d\s.]+$', val):
                    num_count += 1
        if num_count / len(rows) > 0.8:
            return True

    if rows:
        first_cols = [r[0] if r else "" for r in rows]
        from collections import Counter
        counter = Counter(first_cols)
        most_common = counter.most_common(1)
        if most_common and most_common[0][1] / len(rows) > threshold:
            return True

    return False


def _build_pdf_pipeline_options(a):
    from docling.datamodel.accelerator_options import AcceleratorOptions
    from docling.datamodel.pipeline_options import PdfPipelineOptions, RapidOcrOptions, TableStructureOptions, TesseractCliOcrOptions

    use_ocr = str(os.getenv("DOCLING_ENABLE_PDF_OCR", "1")).strip().lower() not in {"0", "false", "no"}
    ocr_langs = [part.strip() for part in os.getenv("DOCLING_OCR_LANG", "ru,en").split(",") if part.strip()]
    ocr_engine = os.getenv("DOCLING_OCR_ENGINE", "tesseract").strip().lower() or "tesseract"
    ocr_backend = os.getenv("DOCLING_RAPIDOCR_BACKEND", "torch").strip().lower() or "torch"
    force_full_page = str(os.getenv("DOCLING_FORCE_FULL_PAGE_OCR", "1")).strip().lower() in {"1", "true", "yes"}
    accelerator_device = a.device if a.device in {"cpu", "cuda"} else "auto"

    if ocr_engine == "tesseract":
        tesseract_langs = []
        for lang in ocr_langs:
            normalized = lang.strip().lower()
            if normalized in {"ru", "rus", "russian"}:
                tesseract_langs.append("rus")
            elif normalized in {"en", "eng", "english"}:
                tesseract_langs.append("eng")
            elif normalized:
                tesseract_langs.append(normalized)
        if not tesseract_langs:
            tesseract_langs = ["rus", "eng"]
        ocr_options = TesseractCliOcrOptions(
            lang=tesseract_langs,
            force_full_page_ocr=force_full_page,
        )
    else:
        ocr_options = RapidOcrOptions(
            lang=ocr_langs,
            backend=ocr_backend,
            force_full_page_ocr=force_full_page,
        )

    if os.getenv("DEBUG_TRACE_TESSERACT"):
        print(f"DEBUG_PIPELINE: use_ocr={use_ocr} ocr_engine={ocr_engine!r} "
              f"ocr_options_type={type(ocr_options).__name__} lang={getattr(ocr_options, 'lang', None)} "
              f"force_full_page={force_full_page}", file=sys.stderr, flush=True)

    return PdfPipelineOptions(
        accelerator_options=AcceleratorOptions(device=accelerator_device),
        do_ocr=use_ocr,
        force_backend_text=False,
        ocr_options=ocr_options,
        do_table_structure=True,
        table_structure_options=TableStructureOptions(device=a.device),
        do_image_analysis=False,
        do_code_enrichment=True,
    )


def convert(a):
    from docling.document_converter import DocumentConverter, PdfFormatOption
    from docling.datamodel.base_models import InputFormat
    from docling_core.types.doc import TableItem, TextItem
    from collections import Counter

    print("⏳ Настройка пайплайна...")
    converter_kwargs = {}
    if Path(a.input).suffix.lower() == ".pdf":
        converter_kwargs["format_options"] = {
            InputFormat.PDF: PdfFormatOption(pipeline_options=_build_pdf_pipeline_options(a))
        }

    converter = DocumentConverter(**converter_kwargs)
    converter.progress_bar = True

    print(f"🔄 Начинаю конвертацию файла: {a.input}")
    start_time = time.time()

    result = converter.convert(a.input)

    elapsed = time.time() - start_time
    print(f"✅ Конвертация завершена за {elapsed:.1f} сек. Обрабатываю результат...")

    doc = result.document
    print(f"📄 Документ: {len(list(doc.iterate_items()))} элементов")

    table_counter = 0
    out_lines = [build_metadata_header(a), f"\n# {a.doc_name}\n"]

    heading_stack = []
    pending_heading = ""
    last_added_heading = ""

    for idx, (item, _level) in enumerate(doc.iterate_items()):
        if idx % 50 == 0:
            print(f"   Обработано {idx} элементов...")

        if isinstance(item, TableItem):
            table_counter += 1

            page_num = None
            if hasattr(item, "prov") and item.prov:
                page_num = item.prov.page_no if hasattr(item.prov, "page_no") else None

            headers, rows = get_table_dataframe(item, doc)
            if not rows:
                print(f"⚠️  Таблица {table_counter} — пуста, пропущена")
                continue

            heading = pending_heading or f"Table {table_counter}"

            if is_toc_table(headers, rows, threshold=0.7):
                print(f"🔖 Таблица {table_counter} ('{heading}') определена как оглавление — пропускаем")
                continue

            if heading_stack:
                last_heading = heading_stack[-1]
                clean_heading = re.sub(r'^\d+[\._]?\s*', '', last_heading)
                slug_base = slugify(clean_heading, max_words=4) or "table"
            else:
                slug_base = "table"

            slug = f"{slug_base}_{table_counter}"

            out_lines.append(f"\n### {heading}\n")
            if a.keep_original_table:
                out_lines.append(render_original_table_md(headers, rows))
            out_lines.extend(flatten_table(headers, rows, slug, page=page_num))

        elif isinstance(item, TextItem):
            label = getattr(item, "label", "")
            text = (item.text or "").strip()
            if not text:
                continue
            if label in ("section_header", "title"):
                if text != last_added_heading:
                    heading_stack.append(text)
                    if len(heading_stack) > 10:
                        heading_stack.pop(0)
                    pending_heading = text
                    last_added_heading = text
                    out_lines.append(f"\n## {text}\n")
            else:
                out_lines.append(text)

    output_path = Path(a.output)
    if output_path.is_dir():
        output_path = output_path / f"{Path(a.input).stem}.md"
    output_path.write_text("\n\n".join(out_lines), encoding="utf-8")
    print(f"✅ Готово: {table_counter} таблиц обработано → {output_path}")


def upload_to_dify(a):
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
    ap.add_argument("output", help="путь к выходному .md (или папка, тогда имя будет взято из входного)")
    ap.add_argument("--doc-name", required=True)
    ap.add_argument("--product", required=True)
    ap.add_argument("--doc-type", required=True, help="release_notes | whats_new | manual | ...")
    ap.add_argument("--version", default="")
    ap.add_argument("--is-latest", default="true")
    ap.add_argument("--keep-original-table", action="store_true",
                    help="дублировать исходную markdown-таблицу перед шардированными строками")
    ap.add_argument("--upload", action="store_true", help="залить результат в Dify KB через Dataset API")
    ap.add_argument("--dify-base-url", default="http://localhost")
    ap.add_argument("--dataset-id", default="")
    ap.add_argument("--dataset-api-key", default="")
    ap.add_argument("--device", default="cpu", choices=["cpu", "cuda"],
                    help="устройство для инференса (cpu/cuda)")
    a = ap.parse_args()

    a.is_latest = a.is_latest.lower() in ("true", "1", "yes")

    convert(a)

    if a.upload:
        if not (a.dataset_id and a.dataset_api_key):
            print("ERROR: --upload требует --dataset-id и --dataset-api-key", file=sys.stderr)
            sys.exit(1)
        upload_to_dify(a)


if __name__ == "__main__":
    main()
