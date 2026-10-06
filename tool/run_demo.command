#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
if [[ ! -d build/web ]]; then
  flutter pub get
  flutter build web --release
fi
print 'Abre http://127.0.0.1:8777 en Safari o Chrome. Para salir, pulsa Control+C.'
python3 -m http.server 8777 --bind 127.0.0.1 --directory build/web
