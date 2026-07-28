select id, app_id, version from workflows where graph::text ilike '%extractor%' limit 5;
