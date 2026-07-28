# Патч api/core/rag/extractor/extract_processor.py

## Куда врезаться
Ты уже нашёл точку: `WordExtractor.extract()` возвращает
`list[Document(page_content=вся_markdown_строка)]`, сегментация
(parent `\n#`, child `\n\n`) идёт ПОСЛЕ, отдельно. Значит достаточно
подменить, какой extractor вызывается для `.docx`/`.pdf` — сама
цепочка (extract → segment → embed) не меняется.

## Изменения в extract_processor.py

1. Добавить импорт:
```python
from core.rag.extractor.docling_http_extractor import DoclingHTTPExtractor
```

2. В обеих ветках (`.docx` и `.pdf`) заменить вызов старого экстрактора
   на новый. Если сейчас там примерно так:
```python
if file_extension == ".docx":
    extractor = WordExtractor(file_path)
elif file_extension == ".pdf":
    extractor = PdfExtractor(file_path)
```
   → заменить на:
```python
if file_extension == ".docx":
    extractor = DoclingHTTPExtractor(file_path)
elif file_extension == ".pdf":
    extractor = DoclingHTTPExtractor(file_path)
```
   (сам `DoclingHTTPExtractor` внутри умеет фолбэкнуться на старые
   `WordExtractor`/`PdfExtractor`, если `docling-intake` недоступен —
   см. docling_http_extractor.py, метод `_fallback_extract`.)

## Docker-compose — образ api

Пересобрать `dify-api-docling:1.15.0` теперь легковесно — НЕ нужен
torch/docling, только requests (уже есть в зависимостях api-образа
почти наверняка, но проверь).

```dockerfile
# docker/dify-api-docling/Dockerfile
FROM langgenius/dify-api:1.15.0
COPY docling_http_extractor.py /app/api/core/rag/extractor/docling_http_extractor.py
COPY extract_processor.py /app/api/core/rag/extractor/extract_processor.py
```

docker-compose.yaml: сервисы `api`, `api_websocket`, `worker`,
`worker_beat` — на образ `dify-api-docling:1.15.0` (как и планировалось
раньше), но теперь сборка занимает секунды, а не десятки минут — риск
с BuildKit-кэшем для CUDA больше не актуален для ЭТОГО образа (он
остаётся только для самого `docling-intake`).

## Сеть
`docling-intake` и `api`/`worker` должны быть в одной docker-сети
(`docker_default`), чтобы резолвился хост `docling-intake` из
`DOCLING_INTAKE_URL`.

## Проверка
1. `docker compose up -d --build api worker docling-intake`
2. Загрузить `.docx` через Dify UI → проверить в логах `worker`, что
   ушёл запрос на `docling-intake:8090` (не старый WordExtractor)
3. Проверить сегменты документа в БД — таблицы должны быть
   пошардированы построчно (`[TABLE: slug | row N/M]`), как раньше
   было только при ручных прогонах shard_tables.py
4. Отключить `docling-intake` (`docker compose stop docling-intake`) и
   повторить загрузку — должен сработать фолбэк на старый
   WordExtractor/PdfExtractor, индексация не должна упасть с ошибкой
