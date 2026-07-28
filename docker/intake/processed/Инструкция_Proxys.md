[doc_name] Инструкция_Proxys
[product] DIFY
[doc_type] Инструкция
[version] -
[version_major] -
[is_latest] true
[source_file] Инструкция_Proxys.pdf



# Инструкция_Proxys



## Настройка локального прокси-хаба на macOS для PyCharm/Junie, браузера и Telegram


======================================================================

Универсальный шлюз через pproxy: один раз настраиваем, дальше все приложения ходят

через 127.0.0.1 без необходимости вводить логин/пароль провайдера в каждом из них.


## ЗАЧЕМ ЭТО НУЖНО


────────────────

Junie / JetBrains AI работают через прокси с авторизацией (без pproxy - не работают)

Креды провайдера хранятся в одном месте, не светятся в настройках приложений

Меняется провайдер - правится одна строка, все приложения подхватывают

pproxy крутится фоном через launchd, автозапуск при загрузке Mac


## ГДЕ БРАТЬ ПРОКСИ


─────────────────

Магазин прокси: proxys.io/ru

Менеджер прокси для браузера: Proxy-Cheap Proxy Manager (расширение)


## ЧТО ПОНАДОБИТСЯ ОТ ПРОВАЙДЕРА


──────────────────────────────

IP:           <PROXY_IP>

HTTP-порт:    <HTTP_PORT>

SOCKS5-порт:  <SOCKS_PORT>   (опционально, можно обойтись только HTTP)

Логин:        <USER>

Пароль:       <PASS>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━


## Шаг 1. Установка pproxy через pipx


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━

# Если pipx ещё нет brew install pipx pipx ensurepath

# Поставить pproxy под Python 3.13 (важно - на 3.14 он падает)

brew install python@3.13 pipx install --python /opt/homebrew/bin/python3.13 pproxy

# Проверить путь - пригодится для plist which pproxy


## # Обычно: /Users/USERNAME/.local/bin/pproxy (это симлинк) # Реальный путь к бинарнику в venv pipx - надёжнее для launchd: ls -la ~/.local/pipx/venvs/pproxy/bin/pproxy [!] В plist лучше указывать прямой путь к бинарнику ~/.local/pipx/venvs/pproxy/bin/pproxy, а не симлинк launchd с симлинками иногда ведёт себя нестабильно. Шаг 2. Ручная проверка, что прокси работает pproxy -l http://127.0.0.1:3128 -r "http://<PROXY_IP>:<HTTP_PORT>#<USER>:<PASS>" -vv [!] Важно: в pproxy логин/пароль апстрима указываются ПОСЛЕ #, а не как user:pass@host. Иначе получите ошибку «argument -r: existing ciphers: [...]» - pproxy интерпретирует часть URL как имя шифра. Также обязательно берите URL в кавычки - символ # в shell означает комментарий и без кавычек URL обрежется. В другом терминале: curl -x http://127.0.0.1:3128 https://api.ipify.org Должен вернуть <PROXY_IP>. Останавливаем Ctrl+C. Шаг 3. Автозапуск через launchd Создать файл ~/Library/LaunchAgents/com.user.pproxy.plist: <?xml version="1.0" encoding="UTF-8"?> <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTD/PropertyList-1.0.dtd"> <plist version="1.0"> <dict> <key>Label</key> <string>com.user.pproxy</string> <key>ProgramArguments</key> <array> <string>/Users/USERNAME/.local/pipx/venvs/pproxy/bin/pproxy</string> <string>-l</string>


<string>http://127.0.0.1:3128</string> <string>-l</string> <string>socks5://127.0.0.1:1080</string> <string>-r</string> <string>http://<PROXY_IP>:<HTTP_PORT>#<USER>:<PASS></string> </array> <key>RunAtLoad</key> <true/> <key>KeepAlive</key> <true/> <key>StandardOutPath</key> <string>/tmp/pproxy.out.log</string> <key>StandardErrorPath</key> <string>/tmp/pproxy.err.log</string> </dict> </plist> Что заменить: - USERNAME          → ваше имя пользователя (узнать: whoami) - <PROXY_IP>        → IP провайдера - <HTTP_PORT>       → HTTP-порт провайдера - <USER> / <PASS>   → логин и пароль провайдера Требования к XML-файлу: - Строка <?xml ... ?> должна быть самой первой, без пробелов перед ней - Никаких лишних отступов в начале строк документа Загрузить и проверить: # Проверить, что plist валидный plutil -lint ~/Library/LaunchAgents/com.user.pproxy.plist # Загрузить (современный способ) launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.pproxy.plist # Проверить статус - должен быть PID и exit code 0 launchctl list | grep pproxy # Ожидаем: <PID>  0  com.user.pproxy # Если первое поле "-" и второе не "0" - процесс упал, см. логи # Проверка работы curl -x http://127.0.0.1:3128 https://api.ipify.org curl --socks5 127.0.0.1:1080 https://api.ipify.org Оба curl должны вернуть <PROXY_IP>.


## Шаг 4. Подключение приложений



### Шаг 4. Подключение приложений


[TABLE: шаг_4_подключение_приложений_1 | row 1/1]
Приложение: PyCharm / Junie Браузер Telegram Desktop Git / ssh / curl; Адрес: 127.0.0.1:3128 HTTP 127.0.0.1:3128 HTTP 127.0.0.1:1080 127.0.0.1:1080 SOCKS5; Протокол Где настраивается: Settings → HTTP Proxy → Manual SwitchyOmega 3 или Proxy-Cheap SOCKS5 Settings → Advanced → Connection По месту

─────────────────────────────────────────────────────────

Авторизация не нужна нигде - pproxy сам подставит креды апстриму.

Bypass-список для корпоративных доменов

────────────────────────────────────────

Везде, где есть поле «No proxy for» / «Bypass list»:

<local> 127.0.0.1/8 192.168.0.0/16 10.0.0.0/8 alfaintra.net *.alfaintra.net alfabank.ru *.alfabank.ru

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━━━━

Управление и диагностика

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━━━━

Команды управления агентом:

# Остановить

launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.pproxy.plist

# Запустить

launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.pproxy.plist

# Принудительный рестарт launchctl kickstart -k gui/$(id -u)/com.user.pproxy

# Подробный статус: PID, exit code, окружение

launchctl print gui/$(id -u)/com.user.pproxy


## # Логи в реальном времени


tail -f /tmp/pproxy.err.log tail -f /tmp/pproxy.out.log

[!] Старые команды launchctl load/unload считаются устаревшими с macOS 10.10 и часто падают с невнятным «5: Input/output error».

Используйте bootstrap / bootout.


## ЧАСТЫЕ ПРОБЛЕМЫ И РЕШЕНИЯ


──────────────────────────


## «Load failed: 5: Input/output error» при launchctl load


Причина:  невалидный XML (часто - пробелы перед <?xml ...?>) Решение:  plutil -lint <plist>, затем launchctl bootstrap gui/$(id -u) <plist>


## launchctl list показывает «-  2  com.user.pproxy»


Причина:  процесс падает при старте, exit code 2 = ошибка аргументов

Решение:  запустить команду из ProgramArguments вручную - увидите реальную ошибку


## «argument -r: existing ciphers: ['aes-128-cfb', ...]»


Причина:  неправильный синтаксис URL апстрима (user:pass@host) Решение:  правильный формат - http://host:port#user:pass (в кавычках в shell)


## «RuntimeError: There is no current event loop»


Причина:  pproxy поставлен под Python 3.14 (deprecated API удалено) Решение:  pipx reinstall --python /opt/homebrew/bin/python3.13 pproxy


## «address already in use» при ручном запуске


Причина:  агент уже работает в фоне - это нормально Решение:  тестировать на другом порту или launchctl bootout перед ручным тестом


## Junie не работает после настройки


Причина:  старые/недоверенные сертификаты

Решение:  Settings → Tools → Server Certificates → Accept non-trusted


## Браузер не пускает на 127.0.0.1


Причина:  защита Chrome против SSRF

Решение:  использовать SwitchyOmega 3 или Proxy-Cheap Proxy Manager


## Логи /tmp/pproxy.*.log пустые, но процесс падает


Причина:  падает до инициализации логирования (не нашёл бинарник / проблема с симлинком)

Решение:  в plist указать прямой путь ~/.local/pipx/venvs/pproxy/bin/pproxy


## ЕСЛИ НУЖЕН SOCKS5-АПСТРИМ ВМЕСТО HTTP


───────────────────────────────────────

В строке -r в plist заменить на:

socks5://<PROXY_IP>:<SOCKS_PORT>#<USER>:<PASS>

Иногда работает чуть быстрее, выходной IP тот же.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━

Итог: все приложения видят локальный прокси без авторизации, pproxy под капотом подставляет креды и шлёт трафик провайдеру.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━