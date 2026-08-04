#!/bin/bash
set -e

# -----------------------------------------------------------------------------
# Build script para Flutter Web no Vercel.
# Variáveis de ambiente do Vercel são convertidas em --dart-define para que o
# Flutter consiga lê-las em tempo de compilação via String.fromEnvironment.
# -----------------------------------------------------------------------------

# Instala Flutter na build do Vercel (se ainda não estiver cacheado).
FLUTTER_VERSION=${FLUTTER_VERSION:-stable}

if [ ! -d "$HOME/flutter" ]; then
  echo "Instalando Flutter $FLUTTER_VERSION..."
  git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" --depth 1 "$HOME/flutter"
fi

export PATH="$HOME/flutter/bin:$HOME/flutter/bin/cache/dart-sdk/bin:$PATH"

flutter config --no-analytics
flutter config --enable-web

# Diagnóstico inicial (não expõe segredos completos).
echo "== DIAGNÓSTICO DO AMBIENTE =="
echo "Shell: $SHELL"
echo "Bash versão: $BASH_VERSION"
echo "Flutter: $(which flutter)"
echo "SUPABASE_URL definida: $([ -n "$SUPABASE_URL" ] && echo sim || echo não)"
echo "SUPABASE_PUBLISHABLE_KEY definida: $([ -n "$SUPABASE_PUBLISHABLE_KEY" ] && echo sim || echo não)"
echo "FLUTTER_ENV: ${FLUTTER_ENV:-<ausente>}"
echo "=============================="

flutter doctor
flutter pub get

# Coleta variáveis de ambiente do Vercel (ou deixa vazio se ausente).
SUPABASE_URL="${SUPABASE_URL:-}"
SUPABASE_PUBLISHABLE_KEY="${SUPABASE_PUBLISHABLE_KEY:-}"
FLUTTER_ENV="${FLUTTER_ENV:-}"

# Argumentos base do build.
BUILD_ARGS=(
  web
  --release
  --dart-define=SUPABASE_URL="$SUPABASE_URL"
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"
)

# NUNCA passa FLUTTER_ENV=dev em produção. Se por algum motivo a variável
# estiver definida como "dev" no dashboard da Vercel, o script a ignora para
# evitar ativação acidental do modo mock no ambiente de produção.
if [ -n "$FLUTTER_ENV" ] && [ "$FLUTTER_ENV" != "dev" ]; then
  BUILD_ARGS+=(--dart-define=FLUTTER_ENV="$FLUTTER_ENV")
fi

# Em produção, o padrão é NÃO definir FLUTTER_ENV. Isso faz com que
# SupabaseConfig.isDev seja false e o modo mock nunca seja ativado.

echo "Iniciando build Flutter Web para Vercel..."
echo "Argumentos: ${BUILD_ARGS[*]}"
flutter build "${BUILD_ARGS[@]}"

# Garante que o Vercel sirva a pasta correta
mkdir -p build/web
echo "Conteúdo de build/web:"
ls -la build/web
