"""
core/rag/extractor/docling_http_extractor.py

Лёгкий HTTP-клиент к сервису docling-intake. Заменяет старую задумку
"WordExtractor → DoclingShardedWordExtractor" (которая требовала
torch/docling прямо в api-образе и никогда реально не собиралась).

Метаданные (doc_name/product/doc_type/version) на этом этапе НЕ
передаются — при обычной загрузке через Dify UI их ещё нет (см.
открытый вопрос про метаданные для PDF/DOCX). docling-intake в этом
случае просто подставит заглушки и вернёт улучшенную структуру текста
(таблицы шардированы построчно), без финальной метаданной документа.
"""

import logging

import requests

from core.rag.extractor.extractor_base import BaseExtractor
from core.rag.models.document import Document

logger = logging.getLogger(__name__)

# TODO: вынести в конфиг Dify (env / settings), не хардкодить хост:порт
DOCLING_INTAKE_URL = "http://docling-intake:8090/ingestion/extract"
REQUEST_TIMEOUT_S = 300


class DoclingHTTPExtractor(BaseExtractor):
    """Заменяет WordExtractor/PdfExtractor для .docx/.pdf через docling-intake."""

    def __init__(self, file_path: str):
        self._file_path = file_path

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
            # безопасный фолбэк — не роняем индексацию, если сервис недоступен
            return self._fallback_extract()

        markdown = resp.json()["markdown"]
        return [Document(page_content=markdown)]

    def _fallback_extract(self) -> list[Document]:
        # тот же импорт, что и раньше в extract_processor.py, вызывается
        # только если docling-intake недоступен/упал
        from core.rag.extractor.word_extractor import WordExtractor
        from core.rag.extractor.pdf_extractor import PdfExtractor

        if self._file_path.lower().endswith(".docx"):
            return WordExtractor(self._file_path).extract()
        return PdfExtractor(self._file_path).extract()
