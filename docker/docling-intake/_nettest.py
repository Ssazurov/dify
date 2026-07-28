import socket
try:
    print("resolved:", socket.gethostbyname("docling-intake"))
except Exception as e:
    print("DNS FAILED:", repr(e))

import requests
try:
    r = requests.get("http://docling-intake:8090/health", timeout=5)
    print("HTTP OK:", r.status_code, r.text)
except Exception as e:
    print("HTTP FAILED:", repr(e))
