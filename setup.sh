#!/usr/bin/env bash
# Setup e Restauração de Scripts e Atalhos
# Utilizado para configurar seu ambiente pela primeira vez ou após formatação do sistema.
#
# Uso:
#   ./setup.sh
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
PROGRAMS_DIR="${PROGRAMS_DIR:-$HOME/Programs}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
info() { printf '\033[1;32m[INFO]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[AVISO]\033[0m %s\n' "$*" >&2; }

printf "\n\033[1;37m=== Configuração do Repositório de Scripts ===\033[0m\n"
printf " Repositório : \033[1;36m%s\033[0m\n" "$REPO_DIR"
printf " Binários    : %s\n" "$BIN_DIR"
printf " Atalhos     : %s\n" "$APPS_DIR"
printf "\033[1;37m==============================================\033[0m\n\n"

# 1. Criar diretórios essenciais
log "Criando pastas essenciais do sistema..."
mkdir -p "$BIN_DIR" "$APPS_DIR" "$HOME/.local/share/antigravity" "$PROGRAMS_DIR"

# 2. Configurar permissões de execução dos scripts
log "Garantindo permissões de execução nos scripts..."
chmod +x "$REPO_DIR/antigravity/update-antigravity.sh"
chmod +x "$REPO_DIR/crealityprint/extract-crealityprint.sh"

# 3. Criar links simbólicos globais no ~/.local/bin
log "Criando links simbólicos no ~/.local/bin..."
ln -sf "$REPO_DIR/antigravity/update-antigravity.sh" "$BIN_DIR/update-antigravity"
ln -sf "$REPO_DIR/crealityprint/extract-crealityprint.sh" "$BIN_DIR/extract-crealityprint"

# 4. Configurar Módulo Antigravity
log "Configurando ambiente do Antigravity..."
# Backup permanente do ícone no XDG Data Home
cp -p "$REPO_DIR/antigravity/icon2.png" "$HOME/.local/share/antigravity/icon2.png"

# Atalho .desktop
if [[ -f "$REPO_DIR/antigravity/Antigravity.desktop" ]]; then
  cp -p "$REPO_DIR/antigravity/Antigravity.desktop" "$APPS_DIR/Antigravity.desktop"
  chmod +x "$APPS_DIR/Antigravity.desktop" || true
fi

# Links e ícones dentro de ~/Programs/Antigravity (se a pasta já existir)
if [[ -d "$PROGRAMS_DIR/Antigravity" ]]; then
  ln -sf "$REPO_DIR/antigravity/update-antigravity.sh" "$PROGRAMS_DIR/Antigravity/update-antigravity.sh"
  if [[ ! -f "$PROGRAMS_DIR/Antigravity/icon2.png" ]]; then
    cp -p "$REPO_DIR/antigravity/icon2.png" "$PROGRAMS_DIR/Antigravity/icon2.png"
  fi
fi

# 5. Configurar Módulo CrealityPrint
log "Configurando ambiente do CrealityPrint..."
if [[ -f "$REPO_DIR/crealityprint/crealityprint.desktop" ]]; then
  cp -p "$REPO_DIR/crealityprint/crealityprint.desktop" "$APPS_DIR/crealityprint.desktop"
fi

if [[ -d "$PROGRAMS_DIR/CrealityPrint" ]]; then
  ln -sf "$REPO_DIR/crealityprint/extract-crealityprint.sh" "$PROGRAMS_DIR/CrealityPrint/extract-crealityprint.sh"
fi

# 6. Atualizar banco de dados de atalhos do desktop
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS_DIR" 2>/dev/null || true
fi

printf "\n\033[1;32m✔ Ambiente configurado com sucesso!\033[0m\n\n"
printf "Comandos globais disponíveis no seu terminal:\n"
printf "  - \033[1;36mupdate-antigravity\033[0m   -> %s/antigravity/update-antigravity.sh\n" "$REPO_DIR"
printf "  - \033[1;36mextract-crealityprint\033[0m-> %s/crealityprint/extract-crealityprint.sh\n\n" "$REPO_DIR"
