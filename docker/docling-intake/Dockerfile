# Расширяет твой УЖЕ рабочий образ docling-intake (в нём CUDA torch/docling
# подтверждены рабочими через `docker compose run`) — здесь НЕ пересобирается
# ничего тяжёлого, только добавляется тонкий API-слой поверх.
#
# Если у тебя это отдельный именованный образ — поставь его тег ниже.
# Если раньше он собирался inline через docker-compose `build:`, оставь как есть
# и просто пропиши эти 3 строки в конец существующего Dockerfile вместо
# отдельного файла.
ARG BASE_IMAGE=docker-docling-intake:latest
FROM ${BASE_IMAGE}

WORKDIR /app

# tesseract-ocr baked in — раньше ставился вручную apt-get внутри
# контейнера и слетал при каждом docker rm/пересоздании (issue #76).
# rus/eng — языки, используемые в DOCLING_OCR_LANG (shard_tables.py).
RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr tesseract-ocr-rus tesseract-ocr-eng \
    && rm -rf /var/lib/apt/lists/*

COPY requirements-api.txt .
RUN pip install --no-cache-dir -r requirements-api.txt

COPY main.py .

EXPOSE 8090

# Базовый образ (docker-docling-intake:latest) имеет свой ENTRYPOINT
# ["python", "shard_tables.py"] — без сброса CMD ниже стал бы просто
# аргументами к нему, а не отдельной командой. Сбрасываем явно.
ENTRYPOINT []

# Сервисный режим по умолчанию (для `docker compose up`).
# Разовый CLI-прогон по-прежнему доступен через:
#   docker compose run --rm --entrypoint python docling-intake shard_tables.py ...
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8090"]
