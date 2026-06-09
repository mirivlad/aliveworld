#!/usr/bin/env bash
# Подключиться к серверной консоли Luanti через docker attach.
# Выход: Ctrl+P затем Ctrl+Q (не нажимайте Ctrl+C — это остановит сервер).
set -euo pipefail

exec docker attach luanti-aliveworld
