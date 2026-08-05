#!/bin/sh
set -e

# -----------------------------------------------------------------------------
# Build script para Flutter Web no Vercel.
# Variáveis de ambiente do Vercel são convertidas em --dart-define.
# -----------------------------------------------------------------------------

# Garante que o Flutter esteja disponível (cache entre builds).
if [ ! -d "$HOME/flutter" ]; then
  echo "Cache do Flutter não encontrado. Clonando..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi

export PATH="$HOME/flutter/bin:$HOME/flutter/bin/cache/dart-sdk/bin:$PATH"

flutter config --no-analytics > /dev/null
flutter config --enable-web > /dev/null
flutter pub get

# Diagnóstico (não expõe segredos completos).
echo "== DIAGNÓSTICO DO AMBIENTE =="
echo "Shell: $(readlink /proc/$$/exe 2>/dev/null || echo $SHELL)"
echo "Flutter: $(which flutter)"
echo "SUPABASE_URL definida: $([ -n "$SUPABASE_URL" ] && echo sim || echo não)"
echo "SUPABASE_PUBLISHABLE_KEY definida: $([ -n "$SUPABASE_PUBLISHABLE_KEY" ] && echo sim || echo não)"
echo "FLUTTER_ENV: ${FLUTTER_ENV:-<ausente>}"
echo "=============================="

# Coleta variáveis de ambiente.
SUPABASE_URL="${SUPABASE_URL:-}"
SUPABASE_PUBLISHABLE_KEY="${SUPABASE_PUBLISHABLE_KEY:-}"
FLUTTER_ENV="${FLUTTER_ENV:-}"

# Argumentos base do build.
BUILD_ARGS="web --release --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"

# NUNCA passa FLUTTER_ENV=dev em produção.
if [ -n "$FLUTTER_ENV" ] && [ "$FLUTTER_ENV" != "dev" ]; then
  BUILD_ARGS="$BUILD_ARGS --dart-define=FLUTTER_ENV=$FLUTTER_ENV"
fi

echo "Iniciando build Flutter Web para Vercel..."
echo "flutter build $BUILD_ARGS"
flutter build $BUILD_ARGS

# Garante que o Vercel sirva a pasta correta.
mkdir -p build/web
echo "Conteúdo de build/web:"
ls -la build/web
