"""
GAR docling-intake — HTTP-обёртка над shard_tables.py.

Раньше запускался так:
  docker compose run --rm \
    -v "$(pwd)/shard_tables.py:/app/shard_tables.py" \
    docling-intake \
    /data/incoming/AG.pdf /data/processed/AG1.md \
    --doc-name "RN1" --product "DIFY" --doc-type "Инструкция" \
    --version "-" --device cuda

Этот сервис делает ровно то же самое (тот же subprocess-вызов
shard_tables.py с теми же флагами), но по HTTP, как постоянно
работающий процесс вместо `docker compose run` на каждый файл.
"""

import logging
import subprocess
import tempfile
import uuid
from pathlib import Path

from fastapi import FastAPI, UploadFile, File, Form, HTTPException

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("docling-intake")

app = FastAPI(title="GAR docling-intake")

SCRIPT_PATH = Path(__file__).parent / "shard_tables.py"
ALLOWED_EXT = {".pdf", ".docx", ".md"}
DEFAULT_DEVICE = "cuda"
SUBPROCESS_TIMEOUT_S = 600  # таблицы/большие PDF на CUDA не должны занимать дольше


@app.get("/health")
def health():
    return {"status": "ok", "script_found": SCRIPT_PATH.exists()}


@app.post("/ingestion/extract")
async def extract(
    file: UploadFile = File(...),
    doc_name: str = Form(None),
    product: str = Form(None),
    doc_type: str = Form(None),
    version: str = Form(None),
    device: str = Form(DEFAULT_DEVICE),
):
    """
    Метаданные необязательны: вызывающая сторона (например патч
    extract_processor.py в момент обычной загрузки через Dify UI) может
    их ещё не знать. В этом случае используются заглушки — их задача
    только не сломать shard_tables.py, а не дать финальную метаданную
    документа. Реальные метаданные для PDF/DOCX прикрепляются отдельным
    шагом (Dify metadata API / GAR Core API) поверх уже загруженного
    документа, а не на этапе extract.
    """
    ext = Path(file.filename).suffix.lower()
    if ext not in ALLOWED_EXT:
        raise HTTPException(400, f"unsupported extension: {ext} (allowed: {ALLOWED_EXT})")

    doc_name = doc_name or Path(file.filename).stem
    product = product or "unknown"
    doc_type = doc_type or "unknown"
    version = version or "-"

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_dir_path = Path(tmp_dir)
        job_id = uuid.uuid4().hex[:8]
        input_path = tmp_dir_path / f"{job_id}{ext}"
        output_path = tmp_dir_path / f"{job_id}.md"

        input_path.write_bytes(await file.read())

        cmd = [
            "python",
            str(SCRIPT_PATH),
            str(input_path),
            str(output_path),
            "--doc-name", doc_name,
            "--product", product,
            "--doc-type", doc_type,
            "--version", version,
            "--device", device,
        ]
        logger.info("running: %s", " ".join(cmd))

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=SUBPROCESS_TIMEOUT_S,
            )
        except subprocess.TimeoutExpired:
            raise HTTPException(504, f"shard_tables.py timed out after {SUBPROCESS_TIMEOUT_S}s")

        if result.returncode != 0:
            logger.error("shard_tables.py failed: %s", result.stderr[-4000:])
            raise HTTPException(
                500,
                f"shard_tables.py exited {result.returncode}: {result.stderr[-2000:]}",
            )

        if not output_path.exists():
            raise HTTPException(500, "shard_tables.py exited 0 but produced no output file")

        markdown = output_path.read_text(encoding="utf-8")

    return {
        "source_file": file.filename,
        "doc_name": doc_name,
        "product": product,
        "doc_type": doc_type,
        "version": version,
        "markdown": markdown,
        "char_count": len(markdown),
        "stdout_tail": result.stdout[-1000:],
    }