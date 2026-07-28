"""
core/rag/extractor/docling_http_extractor.py

Лёгкий HTTP-клиент к сервису docling-intake. Метаданные
(doc_name/product/doc_type/version) на этом этапе НЕ передаются —
docling-intake подставит заглушки. Реальные метаданные для PDF/DOCX
прикрепляются отдельным шагом (gar-metadata-worker / Dify metadata API)
поверх уже загруженного документа.
"""

import logging

import requests

from core.rag.extractor.extractor_base import BaseExtractor
from core.rag.models.document import Document

logger = logging.getLogger(__name__)

# TODO: вынести в configs/dify_config, не хардкодить хост:порт
DOCLING_INTAKE_URL = "http://docling-intake:8090/ingestion/extract"
REQUEST_TIMEOUT_S = 300


class DoclingHTTPExtractor(BaseExtractor):
    """Заменяет WordExtractor/PdfExtractor/MarkdownExtractor для .docx/.pdf/.md через docling-intake."""

    def __init__(self, file_path: str, tenant_id: str | None = None, created_by: str | None = None):
        self._file_path = file_path
        self._tenant_id = tenant_id
        self._created_by = created_by

    def extract(self) -> list[Document]:
        try:
            with open(self._file_path, "rb") as f:
                resp = requests.post(
                    DOCLING_INTAKE_URL,
                    files={"file": (self._file_path, f)},
                    timeout=REQUEST_TIMEOUT_S,
                )
            resp.raise_for_status()
        except requests.RequestException:
            logger.exception(
                "docling-intake request failed for %s, falling back to stock extractor",
                self._file_path,
            )
            return self._fallback_extract()

        markdown = resp.json()["markdown"]
        return [Document(page_content=markdown)]

    def _fallback_extract(self) -> list[Document]:
        from core.rag.extractor.word_extractor import WordExtractor
        from core.rag.extractor.pdf_extractor import PdfExtractor
        from core.rag.extractor.markdown_extractor import MarkdownExtractor

        path_lower = self._file_path.lower()
        if path_lower.endswith(".docx"):
            return WordExtractor(self._file_path, self._tenant_id, self._created_by).extract()
        if path_lower.endswith((".md", ".markdown", ".mdx")):
            return MarkdownExtractor(self._file_path, autodetect_encoding=True).extract()
        return PdfExtractor(self._file_path, self._tenant_id, self._created_by).extract()
