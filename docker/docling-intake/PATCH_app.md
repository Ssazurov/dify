# PATCH app.py — filter_document_metadata из конфига

## Что меняется
Убираем хардкод `key.startswith("doc_") or key == "product_version"`,
читаем разрешённые поля из `config/metadata_schema.yaml`. Это чинит
баг с отброшенными cluster/company/subdivision/product/product_name
И даёт per-tenant конфигурируемость, о которой договорились.

## 1. Добавить зависимость
requirements.txt: `PyYAML`

## 2. Добавить загрузку схемы (рядом с DIFY_URL/API_KEY в начале app.py)

```python
import yaml

SCHEMA_PATH = os.getenv("METADATA_SCHEMA_PATH", "config/metadata_schema.yaml")

def load_schema():
    with open(SCHEMA_PATH, encoding="utf-8") as f:
        raw = yaml.safe_load(f)
    return {f["name"]: f for f in raw["fields"]}

METADATA_SCHEMA = load_schema()
MANUAL_FIELDS = {
    name for name, f in METADATA_SCHEMA.items() if f["source"] == "manual"
}
```

## 3. Заменить filter_document_metadata

Было:
```python
def filter_document_metadata(metadata):
    result = {}
    for key, value in metadata.items():
        if key.startswith("doc_") or key == "product_version":
            result[key] = value
    return result
```

Стало:
```python
def filter_document_metadata(metadata):
    result = {}
    for key, value in metadata.items():
        if key in MANUAL_FIELDS:
            result[key] = value
        else:
            print(f"WARN: unknown metadata key '{key}' not in schema, skipped", flush=True)
    return result
```

## 4. (опционально, но рекомендую) — валидация required-полей

Добавить перед `update_metadata(doc_id, document_metadata)` в `process_document`:

```python
    missing_required = [
        name for name, f in METADATA_SCHEMA.items()
        if f.get("required") and f["source"] == "manual" and name not in document_metadata
    ]
    if missing_required:
        print(f"MISSING REQUIRED FIELDS {missing_required}: {doc_id}", flush=True)
        db.mark_failed(doc_id, f"missing required fields: {missing_required}")
        return
```

Сейчас документ без `product`/`doc_type`/`product_version` тихо
проходит как "processed" с пустыми полями — это ломает и версионность,
и Document Search фильтры из бизнес-требований.

## 5. docker-compose / .env

Смонтировать `config/metadata_schema.yaml` в контейнер worker'а:
```yaml
volumes:
  - ./config:/app/config
```

## Не решено этим патчем (осознанно, не задача gar-metadata-worker)
- `version_major`/`is_latest` (derived-поля из схемы) — вычисление
  требует сравнения `product_version` между документами одного
  `product`+`doc_type`, это через Dataset API одним документом за раз
  не сделать эффективно. По архитектуре GAR Platform это должно жить
  в Core API metadata router (у него будет вид на весь датасет), не в
  построчном воркере. Пока просто не заполняются.
- doc_created/doc_approved как Unix timestamp — readme это обещает,
  код этого не делает (создаёт string-поле, не time-поле в Dify).
  Если это реально нужно для сортировки по дате в Document Search —
  скажи, добавлю epoch-конверсию и `"type": "time"` в create_field.
