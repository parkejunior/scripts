#!/usr/bin/env bash
# Script de Atualização do Google Antigravity para Linux
# Mantém o ícone personalizado (icon2.png) e o atalho .desktop intactos.
#
# Uso:
#   update-antigravity                    (detecta automaticamente o tar.gz mais recente em ~/Downloads)
#   update-antigravity arquivo.tar.gz     (utiliza o arquivo especificado)
#   update-antigravity --download         (tenta baixar a versão mais recente via rede)
#   update-antigravity --rollback         (restaura o backup da versão anterior)
#   update-antigravity -y / --yes         (atualização sem confirmação interativa)
#   update-antigravity -f / --force       (ignora aviso de processo em execução)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

PROGRAMS_DIR="${PROGRAMS_DIR:-$HOME/Programs}"
APP_DIR="${ANTIGRAVITY_APP_DIR:-$PROGRAMS_DIR/Antigravity}"
BACKUP_DIR="${ANTIGRAVITY_BACKUP_DIR:-$PROGRAMS_DIR/Antigravity.backup}"
PERM_ICON_DIR="$HOME/.local/share/antigravity"
ICON_NAME="icon2.png"
REPO_ICON="$SCRIPT_DIR/$ICON_NAME"
PERM_ICON_PATH="$PERM_ICON_DIR/$ICON_NAME"
DESKTOP_FILE="$HOME/.local/share/applications/Antigravity.desktop"
REPO_DESKTOP="$SCRIPT_DIR/Antigravity.desktop"
BIN_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_DIR/update-antigravity"
DOWNLOAD_URL_DEFAULT="https://antigravity.google/download"

FORCE=0
ASSUME_YES=0
DO_ROLLBACK=0
DO_DOWNLOAD=0
ARCHIVE_ARG=""

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
info() { printf '\033[1;32m[INFO]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[AVISO]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ERRO]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

usage() {
  cat << EOF
Atualizador do Google Antigravity

Uso:
  $(basename "$0") [opções] [ARQUIVO.tar.gz]

Opções:
  [ARQUIVO.tar.gz]      Caminho para o pacote tar.gz baixado.
  --download            Tenta baixar automaticamente a versão mais recente via terminal.
  --rollback            Restaura o backup da versão anterior ($BACKUP_DIR).
  -y, --yes             Executa a atualização sem pedir confirmação interativa.
  -f, --force           Ignora avisos de aplicativo em execução.
  -h, --help            Exibe esta ajuda e sai.

Exemplos:
  $(basename "$0")
  $(basename "$0") ~/Downloads/Antigravity.tar.gz
  $(basename "$0") --rollback
EOF
}

# Processamento de argumentos
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -y|--yes)
      ASSUME_YES=1
      shift
      ;;
    -f|--force)
      FORCE=1
      shift
      ;;
    --rollback)
      DO_ROLLBACK=1
      shift
      ;;
    --download)
      DO_DOWNLOAD=1
      shift
      ;;
    -*)
      die "Opção desconhecida: $1 (consulte --help)"
      ;;
    *)
      if [[ -z "$ARCHIVE_ARG" ]]; then
        ARCHIVE_ARG="$1"
      else
        die "Múltiplos arquivos informados. Por favor, forneça apenas um arquivo .tar.gz."
      fi
      shift
      ;;
  esac
done

# Garantir backup permanente do icon2.png
save_permanent_icon() {
  mkdir -p "$PERM_ICON_DIR"
  if [[ -f "$REPO_ICON" ]]; then
    cp -p "$REPO_ICON" "$PERM_ICON_PATH"
  elif [[ -f "$APP_DIR/$ICON_NAME" ]]; then
    cp -p "$APP_DIR/$ICON_NAME" "$PERM_ICON_PATH"
  fi
}

# Restaurar icon2.png no diretório de destino
restore_icon() {
  local target_dir="$1"
  if [[ -f "$REPO_ICON" ]]; then
    cp -p "$REPO_ICON" "$target_dir/$ICON_NAME"
    info "Ícone personalizado ($ICON_NAME) restaurado do repositório."
  elif [[ -f "$PERM_ICON_PATH" ]]; then
    cp -p "$PERM_ICON_PATH" "$target_dir/$ICON_NAME"
    info "Ícone personalizado ($ICON_NAME) restaurado do backup local."
  else
    warn "Nenhum ícone de backup encontrado em $PERM_ICON_PATH."
  fi
}

# Assegurar atalho .desktop
ensure_desktop_entry() {
  mkdir -p "$(dirname "$DESKTOP_FILE")"
  if [[ -f "$REPO_DESKTOP" ]]; then
    cp -p "$REPO_DESKTOP" "$DESKTOP_FILE"
  elif [[ ! -f "$DESKTOP_FILE" ]]; then
    log "Criando atalho $DESKTOP_FILE..."
    cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Antigravity
Exec=$APP_DIR/antigravity
Icon=$APP_DIR/$ICON_NAME
Terminal=false
Categories=Development
EOF
    chmod +x "$DESKTOP_FILE" || true
  else
    # Verificar se as linhas Exec e Icon estão corretas
    sed -i "s|^Exec=.*|Exec=$APP_DIR/antigravity|" "$DESKTOP_FILE"
    sed -i "s|^Icon=.*|Icon=$APP_DIR/$ICON_NAME|" "$DESKTOP_FILE"
  fi
  # Atualizar cache de desktop se utilitário existir
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  fi
}

# Assegurar links simbólicos
ensure_symlinks() {
  mkdir -p "$BIN_DIR"
  if [[ "$SCRIPT_PATH" != "$BIN_LINK" ]]; then
    ln -sf "$SCRIPT_PATH" "$BIN_LINK"
  fi
  # Link de conveniência dentro de ~/Programs/Antigravity/
  if [[ -d "$APP_DIR" && "$SCRIPT_PATH" != "$APP_DIR/update-antigravity.sh" ]]; then
    ln -sf "$SCRIPT_PATH" "$APP_DIR/update-antigravity.sh"
  fi
}

# Tratamento de Rollback
if [[ "$DO_ROLLBACK" -eq 1 ]]; then
  log "Iniciando processo de reversão (Rollback)..."
  [[ -d "$BACKUP_DIR" ]] || die "Diretório de backup não encontrado em: $BACKUP_DIR"
  [[ -f "$BACKUP_DIR/antigravity" ]] || die "Backup corrompido: '$BACKUP_DIR/antigravity' não encontrado."

  save_permanent_icon

  log "Restaurando $BACKUP_DIR para $APP_DIR..."
  rm -rf "$APP_DIR"
  cp -a "$BACKUP_DIR" "$APP_DIR"

  restore_icon "$APP_DIR"
  ensure_desktop_entry
  ensure_symlinks

  local_ver="desconhecida"
  [[ -f "$APP_DIR/version" ]] && local_ver="$(cat "$APP_DIR/version")"
  info "Rollback concluído com sucesso! Versão ativa agora: $local_ver"
  exit 0
fi

# Verificar processos em execução
check_running_processes() {
  local pids
  pids=$(pgrep -f "$APP_DIR/antigravity" 2>/dev/null || true)
  if [[ -n "$pids" ]]; then
    warn "O Antigravity parece estar em execução (PIDs: $pids)."
    if [[ "$FORCE" -eq 1 ]]; then
      warn "Opção --force utilizada. Continuando mesmo com o aplicativo aberto..."
    else
      warn "Recomenda-se fechar o Antigravity antes de atualizar para evitar conflito de arquivos."
      printf "Deseja continuar mesmo assim? [s/N]: "
      read -r ans
      if [[ ! "$ans" =~ ^[sS]([iI][mM])?$ ]]; then
        die "Atualização cancelada pelo usuário. Feche o Antigravity e tente novamente."
      fi
    fi
  fi
}

# Função para download automático
download_latest() {
  log "Buscando pacote mais recente do Antigravity..."
  local dest_tar="$HOME/Downloads/Antigravity-latest.tar.gz"

  local manifest_url="https://antigravity-hub-auto-updater-974169037036.us-central1.run.app/manifest/latest-linux.yml"
  local download_url=""

  # Tenta obter a URL a partir do manifesto oficial
  if command -v curl >/dev/null 2>&1; then
    local yml_data
    yml_data=$(curl -sL --max-time 10 "$manifest_url" 2>/dev/null || true)
    if [[ -n "$yml_data" ]]; then
      download_url=$(python3 -c "
import sys, re
data = '''$yml_data'''
for line in data.splitlines():
    m = re.match(r'^\s*url:\s*(.+)$', line)
    if m:
        u = m.group(1).strip().strip('\"\'')
        if 'tar.gz' in u:
            print(u)
            sys.exit(0)
" 2>/dev/null || true)
    fi
  fi

  if [[ -z "$download_url" ]]; then
    warn "Não foi possível resolver o link direto de download automaticamente."
    info "Por favor, baixe o arquivo 'Linux x64 (.tar.gz)' em:"
    printf "  \033[1;36m%s\033[0m\n\n" "$DOWNLOAD_URL_DEFAULT"
    die "Após o download, execute novamente: $(basename "$0")"
  fi

  log "Baixando de: $download_url"
  curl -L --progress-bar -o "$dest_tar" "$download_url" || die "Falha ao baixar o arquivo."
  info "Download concluído: $dest_tar"
  ARCHIVE_ARG="$dest_tar"
}

if [[ "$DO_DOWNLOAD" -eq 1 ]]; then
  download_latest
fi

# Localizar arquivo .tar.gz se não foi fornecido
find_latest_tar() {
  local search_dirs=("$HOME/Downloads" "$PWD")
  local best_file=""
  local best_time=0

  for dir in "${search_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' f; do
      local mtime
      mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
      if (( mtime > best_time )); then
        best_time=$mtime
        best_file="$f"
      fi
    done < <(find "$dir" -maxdepth 2 -type f \( -iname "*antigravity*.tar.gz" -o -iname "*antigravity*.tgz" \) -print0 2>/dev/null)
  done

  printf '%s\n' "$best_file"
}

ARCHIVE_PATH="$ARCHIVE_ARG"
if [[ -z "$ARCHIVE_PATH" ]]; then
  log "Procurando arquivo de atualização recente em ~/Downloads..."
  ARCHIVE_PATH="$(find_latest_tar)"
  if [[ -z "$ARCHIVE_PATH" || ! -f "$ARCHIVE_PATH" ]]; then
    err "Nenhum arquivo Antigravity*.tar.gz encontrado automaticamente."
    info "Baixe a versão x64 (.tar.gz) em: $DOWNLOAD_URL_DEFAULT"
    info "Depois execute: $(basename "$0") ~/Downloads/Antigravity.tar.gz"
    exit 1
  fi
fi

[[ -f "$ARCHIVE_PATH" ]] || die "Arquivo não encontrado: $ARCHIVE_PATH"

# Obter informações das versões
CURRENT_VER="desconhecida"
if [[ -f "$APP_DIR/version" ]]; then
  CURRENT_VER="$(cat "$APP_DIR/version" | tr -d '[:space:]')"
fi

FILE_DATE=$(date -r "$ARCHIVE_PATH" "+%d/%m/%Y às %H:%M:%S" 2>/dev/null || echo "Data desconhecida")
FILE_SIZE=$(du -h "$ARCHIVE_PATH" 2>/dev/null | cut -f1 || echo "")

printf "\n\033[1;37m=== Atualização do Google Antigravity ===\033[0m\n"
printf " Pacote selecionado : \033[1;36m%s\033[0m\n" "$ARCHIVE_PATH"
printf " Tamanho do arquivo : %s\n" "$FILE_SIZE"
printf " Data do pacote     : %s\n" "$FILE_DATE"
printf " Versão atual       : \033[1;33m%s\033[0m\n" "$CURRENT_VER"
printf " Destino            : %s\n" "$APP_DIR"
printf "\033[1;37m=========================================\033[0m\n\n"

if [[ "$ASSUME_YES" -ne 1 ]]; then
  printf "Deseja prosseguir com a instalação? [S/n]: "
  read -r confirm
  if [[ -n "$confirm" && ! "$confirm" =~ ^[sSyY]([iI][mM])?$ ]]; then
    info "Atualização cancelada pelo usuário."
    exit 0
  fi
fi

# Verificar processos em execução antes de modificar arquivos
check_running_processes

# Salvar permanentemente o ícone antes de qualquer modificação
save_permanent_icon

# Preparar diretório temporário para extração segura
TMP_EXTRACT=$(mktemp -d "${TMPDIR:-/tmp}/antigravity-update-XXXXXX")
cleanup() {
  rm -rf "$TMP_EXTRACT"
}
trap cleanup EXIT

log "Validando e extraindo o pacote (isso pode levar alguns segundos)..."
tar -xzf "$ARCHIVE_PATH" -C "$TMP_EXTRACT" || die "Erro ao descompactar o arquivo $ARCHIVE_PATH"

# Localizar raiz dos binários extraídos
PAYLOAD_DIR=""
if [[ -f "$TMP_EXTRACT/antigravity" ]]; then
  PAYLOAD_DIR="$TMP_EXTRACT"
else
  # Procurar subdiretório que contenha o binário antigravity
  cands=()
  while IFS= read -r -d '' cand; do
    cands+=("$(dirname "$cand")")
  done < <(find "$TMP_EXTRACT" -maxdepth 3 -type f -name "antigravity" -print0 2>/dev/null)

  if [[ ${#cands[@]} -gt 0 ]]; then
    PAYLOAD_DIR="${cands[0]}"
  fi
fi

[[ -n "$PAYLOAD_DIR" && -f "$PAYLOAD_DIR/antigravity" ]] || die "Conteúdo inválido: executável 'antigravity' não foi encontrado no arquivo extraído."

NEW_VER="desconhecida"
if [[ -f "$PAYLOAD_DIR/version" ]]; then
  NEW_VER="$(cat "$PAYLOAD_DIR/version" | tr -d '[:space:]')"
fi

# Criar backup da instalação atual
if [[ -d "$APP_DIR" ]]; then
  log "Criando backup da versão atual em $BACKUP_DIR..."
  rm -rf "$BACKUP_DIR"
  cp -a "$APP_DIR" "$BACKUP_DIR"
else
  mkdir -p "$APP_DIR"
fi

log "Instalando nova versão em $APP_DIR..."
# Remove conteúdo anterior do APP_DIR garantindo pasta limpa
find "$APP_DIR" -mindepth 1 -delete 2>/dev/null || rm -rf "${APP_DIR:?}"/*

# Copiar os novos arquivos
cp -a "$PAYLOAD_DIR"/* "$APP_DIR/"

# Restaurar ícone personalizado (icon2.png)
restore_icon "$APP_DIR"

# Garantir permissões de execução
chmod +x "$APP_DIR/antigravity"
if [[ -f "$APP_DIR/chrome-sandbox" ]]; then
  chmod +x "$APP_DIR/chrome-sandbox"
fi

# Atualizar atalho do desktop e links simbólicos
ensure_desktop_entry
ensure_symlinks

printf "\n\033[1;32m✔ Antigravity atualizado com sucesso!\033[0m\n"
printf "  Versão anterior : %s\n" "$CURRENT_VER"
printf "  Nova versão     : \033[1;32m%s\033[0m\n" "$NEW_VER"
printf "  Executável      : %s/antigravity\n" "$APP_DIR"
printf "  Ícone ativo     : %s/%s\n" "$APP_DIR" "$ICON_NAME"
printf "  Atalho desktop  : %s\n" "$DESKTOP_FILE"
printf "  Backup anterior : %s (use --rollback para reverter se necessário)\n\n" "$BACKUP_DIR"
