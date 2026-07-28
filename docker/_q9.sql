select jsonb_pretty(n) from workflows w, jsonb_array_elements(w.graph::jsonb->'nodes') n
where w.id='0a0f0210-cdfe-4f7f-8e4b-561ea27b54cb'
and (n->'data'->>'title') ilike '%extractor%';
