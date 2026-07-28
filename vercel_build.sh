#!/bin/bash
set -e

# Instala Flutter na build do Vercel
FLUTTER_VERSION=${FLUTTER_VERSION:-stable}

if [ ! -d "$HOME/flutter" ]; then
  echo "Instalando Flutter $FLUTTER_VERSION..."
  git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" --depth 1 "$HOME/flutter"
fi

export PATH="$HOME/flutter/bin:$HOME/flutter/bin/cache/dart-sdk/bin:$PATH"

flutter config --no-analytics
flutter doctor
flutter config --enable-web
flutter pub get
flutter build web --release

# Garante que o Vercel sirva a pasta correta
mkdir -p build/web
echo "Conteúdo de build/web:"
ls -la build/web
