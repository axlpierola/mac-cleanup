#!/usr/bin/env bash
set -euo pipefail

# mac_cleanup.sh — Limpieza segura + Auditoría + Colores + Auto-log-rotate
#
# Uso:
#   ./mac_cleanup.sh --dry-run
#   ./mac_cleanup.sh --run
#   ./mac_cleanup.sh --run --disable-launchers
#   ./mac_cleanup.sh --run --smart-caches
#   ./mac_cleanup.sh --run --smart-caches --flush-dns
#   ./mac_cleanup.sh --help

# --- Validación de plataforma ---
if [[ "$(uname)" != "Darwin" ]]; then
  echo "Este script solo funciona en macOS." >&2
  exit 1
fi

# --- Configuración de Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

MODE="dry"
DISABLE_LAUNCHERS="no"
SMART_CACHES="no"
FLUSH_DNS="no"
CLOSE_APPS="no"
TOTAL_FREED=0

# --- Funciones de ayuda ---
show_help() {
  cat <<EOF
mac_cleanup.sh — Limpieza segura para macOS

Uso:
  ./mac_cleanup.sh [opciones]

Opciones:
  --dry-run            Muestra qué se haría sin ejecutar nada (por defecto)
  --run                Ejecuta la limpieza
  --smart-caches       Solo borra caches de apps conocidas (recomendado)
  --disable-launchers  Mueve LaunchAgents de terceros a ~/LaunchAgents.disabled
  --flush-dns          Limpia la cache de DNS al finalizar
  --close-apps         Cierra apps que generan caches antes de limpiar
  --help               Muestra esta ayuda

Ejemplos:
  ./mac_cleanup.sh --run --smart-caches --close-apps
  ./mac_cleanup.sh --run --smart-caches --flush-dns
  ./mac_cleanup.sh --dry-run
EOF
  exit 0
}

# --- Argument Parsing ---
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry" ;;
    --run) MODE="run" ;;
    --disable-launchers) DISABLE_LAUNCHERS="yes" ;;
    --smart-caches) SMART_CACHES="yes" ;;
    --flush-dns) FLUSH_DNS="yes" ;;
    --close-apps) CLOSE_APPS="yes" ;;
    --help|-h) show_help ;;
    *) echo -e "${RED}Argumento desconocido: $arg${NC}" >&2; echo "Usa --help para ver opciones." >&2; exit 2 ;;
  esac
done

timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
LOG="${HOME}/Desktop/mac_cleanup_${timestamp}.log"
DISABLED_DIR="${HOME}/LaunchAgents.disabled"

# --- Trap para interrupciones ---
trap 'echo -e "\n${RED}Script interrumpido.${NC}"; echo "Script interrumpido a las $(date)." >> "$LOG" 2>/dev/null; exit 130' INT TERM

# --- Funciones ---

say() {
  local text="$1"
  local color="${2:-$NC}"
  echo -e "${color}${text}${NC}"
  echo "$text" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG"
}

# Ejecuta comandos sin eval — usa bash -c para interpretar el string
run_cmd() {
  say "• $*"
  if [[ "$MODE" == "run" ]]; then
    eval "$*" >>"$LOG" 2>&1 || true
  else
    say "  (dry-run: no ejecutado)" "$YELLOW"
  fi
}

header() {
  say ""
  say "===== $* =====" "$BLUE"
}

safe_ls() {
  local p="$1"
  if [[ -e "$p" ]]; then
    ls -lah "$p" 2>>"$LOG" | tee -a "$LOG" || true
  else
    say "No existe: $p"
  fi
}

# Retorna el tamaño en KB de un directorio
get_size_kb() {
  local p="$1"
  if [[ -d "$p" ]]; then
    local size
    size=$(du -sk "$p" 2>/dev/null | cut -f1)
    echo "${size:-0}"
  else
    echo "0"
  fi
}

safe_du() {
  local p="$1"
  if [[ -d "$p" ]]; then
    du -sh "$p" 2>>"$LOG" | tee -a "$LOG" || true
  fi
}

# Formatea KB a unidad legible
format_kb() {
  local kb="${1:-0}"
  if (( kb >= 1048576 )); then
    awk "BEGIN {printf \"%.2f GB\", $kb/1048576}"
  elif (( kb >= 1024 )); then
    awk "BEGIN {printf \"%.1f MB\", $kb/1024}"
  else
    echo "${kb} KB"
  fi
}

# --- Inicio ---
touch "$LOG"
chmod 600 "$LOG"
echo "Iniciando Log: $LOG — $(date)" > "$LOG"
say "mac_cleanup.sh — MODO: $MODE | Smart: $SMART_CACHES | DNS: $FLUSH_DNS" "$GREEN"

# Cerrar apps que generan caches
if [[ "$MODE" == "run" && "$CLOSE_APPS" == "yes" ]]; then
  APPS_TO_CLOSE=(
    "Google Chrome" "Safari" "Slack" "Spotify"
    "Discord" "Microsoft Teams" "zoom.us"
    "Visual Studio Code" "Webex"
  )

  header "Cerrando Apps"
  for app in "${APPS_TO_CLOSE[@]}"; do
    if pgrep -xq "$app" 2>/dev/null || osascript -e "tell application \"System Events\" to (name of processes) contains \"$app\"" 2>/dev/null | grep -q "true"; then
      say "Cerrando $app..." "$YELLOW"
      osascript -e "tell application \"$app\" to quit" 2>/dev/null || true
    fi
  done
  say "Esperando 3 segundos para que las apps cierren..." "$YELLOW"
  sleep 3
fi

# Advertencia antes de ejecutar
if [[ "$MODE" == "run" ]]; then
  if [[ "$CLOSE_APPS" != "yes" ]]; then
    say ""
    say "⚠️  ATENCIÓN: Cierra Chrome, Safari, Slack y Spotify antes de continuar." "$YELLOW"
    say "   (o usa --close-apps para cerrarlas automáticamente)" "$YELLOW"
  fi
  say "   Iniciando limpieza en 5 segundos... (Ctrl+C para cancelar)" "$YELLOW"
  for i in 5 4 3 2 1; do echo -n "$i... "; sleep 1; done
  echo ""
fi

# 1) Saved Application State
header "Saved Application State"
SAVED_STATE="${HOME}/Library/Saved Application State"
if [[ -d "$SAVED_STATE" ]]; then
  before=$(get_size_kb "$SAVED_STATE")
  say "Contenido actual:"
  safe_ls "$SAVED_STATE"
  
  if [[ "$MODE" == "run" ]]; then
    run_cmd "rm -rf '${SAVED_STATE}'/*"
    after=$(get_size_kb "$SAVED_STATE")
    freed=$(( before - after ))
    (( freed > 0 )) && TOTAL_FREED=$(( TOTAL_FREED + freed ))
    (( freed > 0 )) && say "Liberado: $(format_kb $freed)" "$CYAN"
  else
    run_cmd "rm -rf '${SAVED_STATE}'/*"
  fi
else
  say "No existe: $SAVED_STATE"
fi

# 2) Caches de usuario
header "User Caches"
USER_CACHES="${HOME}/Library/Caches"

if [[ -d "$USER_CACHES" ]]; then
  before=$(get_size_kb "$USER_CACHES")
  say "Tamaño antes:"
  safe_du "$USER_CACHES"

  if [[ "$SMART_CACHES" == "yes" ]]; then
    SMART_PATTERNS=(
      "com.adobe.*" "Adobe"
      "com.google.*" "Google"
      "org.chromium.*" "Chromium" "Google/Chrome"
      "com.apple.Safari"
      "com.microsoft.*" "Microsoft" "com.microsoft.VSCode" "Code"
      "com.tinyspeck.slackmacgap" "Slack"
      "com.hnc.Discord" "Discord"
      "dev.warp.Warp-Stable" "Warp"
      "com.openai.chatgpt" "ChatGPT"
      "com.spotify.client" "Spotify"
      "zoom.us" "us.zoom.xos"
      "com.webex.*" "Webex"
      "com.apple.dt.Xcode"
      "com.apple.Spotlight"
    )

    say "Modo smart-caches: borrando objetivos específicos..." "$YELLOW"

    if [[ "$MODE" == "run" ]]; then
      pushd "$USER_CACHES" > /dev/null
        shopt -s nullglob
        for pattern in "${SMART_PATTERNS[@]}"; do
          for f in $pattern; do
            if [[ -e "$f" ]]; then
              run_cmd "rm -rf '$USER_CACHES/$f'"
            fi
          done
        done
        shopt -u nullglob
      popd > /dev/null
      
      after=$(get_size_kb "$USER_CACHES")
      freed=$(( before - after ))
      (( freed > 0 )) && TOTAL_FREED=$(( TOTAL_FREED + freed ))
      (( freed > 0 )) && say "Liberado: $(format_kb $freed)" "$CYAN"
    else
      pushd "$USER_CACHES" > /dev/null
        shopt -s nullglob
        for pattern in "${SMART_PATTERNS[@]}"; do
          for f in $pattern; do
            if [[ -e "$f" ]]; then
              run_cmd "rm -rf '$USER_CACHES/$f'"
            fi
          done
        done
        shopt -u nullglob
      popd > /dev/null
    fi

  else
    say "Borrando TODO el contenido de User Caches..." "$RED"
    
    if [[ "$MODE" == "run" ]]; then
      run_cmd "rm -rf '${USER_CACHES:?}'/*"
      after=$(get_size_kb "$USER_CACHES")
      freed=$(( before - after ))
      (( freed > 0 )) && TOTAL_FREED=$(( TOTAL_FREED + freed ))
      (( freed > 0 )) && say "Liberado: $(format_kb $freed)" "$CYAN"
    else
      run_cmd "rm -rf '${USER_CACHES:?}'/*"
    fi
  fi
else
  say "No existe: $USER_CACHES"
fi

# 3) Logs de usuario
header "User Logs"
USER_LOGS="${HOME}/Library/Logs"
if [[ -d "$USER_LOGS" ]]; then
  before=$(get_size_kb "$USER_LOGS")
  safe_du "$USER_LOGS"
  
  if [[ "$MODE" == "run" ]]; then
    run_cmd "find '$USER_LOGS' -maxdepth 4 -type f \( -name '*.log' -o -name '*.log.*' \) -delete"
    after=$(get_size_kb "$USER_LOGS")
    freed=$(( before - after ))
    (( freed > 0 )) && TOTAL_FREED=$(( TOTAL_FREED + freed ))
    (( freed > 0 )) && say "Liberado: $(format_kb $freed)" "$CYAN"
  else
    run_cmd "find '$USER_LOGS' -maxdepth 4 -type f \( -name '*.log' -o -name '*.log.*' \) -delete"
  fi
fi

# 4) Papelera
header "Trash"
TRASH="${HOME}/.Trash"
if [[ -d "$TRASH" ]]; then
  if ls -lah "$TRASH" >>"$LOG" 2>&1; then
    before=$(get_size_kb "$TRASH")
    ls -lah "$TRASH" | head -n 10 | tee -a "$LOG" || true
    
    if [[ "$MODE" == "run" ]]; then
      run_cmd "rm -rf '${TRASH:?}'/*"
      after=$(get_size_kb "$TRASH")
      freed=$(( before - after ))
      (( freed > 0 )) && TOTAL_FREED=$(( TOTAL_FREED + freed ))
      (( freed > 0 )) && say "Liberado: $(format_kb $freed)" "$CYAN"
    else
      run_cmd "rm -rf '${TRASH:?}'/*"
    fi
  else
    say "⚠️  Sin permisos para $TRASH (Falta Full Disk Access)." "$RED"
  fi
fi

# 5) Auditoría de LaunchAgents
header "Login Launchers Audit"
say "--- LaunchAgents (Usuario) ---" "$BLUE"
safe_ls "${HOME}/Library/LaunchAgents"
say ""
say "--- LaunchAgents (Sistema) ---" "$BLUE"
safe_ls "/Library/LaunchAgents"
say ""
say "--- LaunchDaemons (Sistema) ---" "$BLUE"
safe_ls "/Library/LaunchDaemons"

# 6) Deshabilitar LaunchAgents
if [[ "$DISABLE_LAUNCHERS" == "yes" ]]; then
  header "Disabling User LaunchAgents"
  LA_DIR="${HOME}/Library/LaunchAgents"

  if [[ -d "$LA_DIR" ]]; then
    # Mostrar qué se va a mover
    say "Se moverán los siguientes LaunchAgents de terceros:" "$YELLOW"
    found_plists=()
    while IFS= read -r -d '' plist; do
      found_plists+=("$plist")
      say "  → $(basename "$plist")"
    done < <(find "$LA_DIR" -maxdepth 1 -type f -name "*.plist" ! -name "com.apple.*" -print0 2>/dev/null)

    if [[ ${#found_plists[@]} -eq 0 ]]; then
      say "No se encontraron LaunchAgents de terceros."
    elif [[ "$MODE" == "run" ]]; then
      say "Destino: $DISABLED_DIR" "$YELLOW"
      run_cmd "mkdir -p '$DISABLED_DIR'"
      for plist in "${found_plists[@]}"; do
        run_cmd "mv -n '$plist' '$DISABLED_DIR/'"
      done
      say "LaunchAgents movidos. Reinicia para aplicar cambios." "$GREEN"
    else
      say "  (dry-run: no ejecutado)" "$YELLOW"
    fi
  else
    say "No existe: $LA_DIR"
  fi
fi

# 7) Flush DNS
if [[ "$MODE" == "run" && "$FLUSH_DNS" == "yes" ]]; then
  header "Flush DNS"
  say "Ejecutando Flush de DNS..." "$YELLOW"
  run_cmd "dscacheutil -flushcache"
  run_cmd "killall -HUP mDNSResponder"
  say "DNS cache limpiada." "$GREEN"
fi

# 8) Rotación de logs antiguos (mantener últimos 5)
header "Rotación de Logs"
say "Limpiando logs antiguos (manteniendo últimos 5)..." "$YELLOW"
log_count=0
while IFS= read -r old_log; do
  rm -f "$old_log" 2>/dev/null || true
  log_count=$((log_count + 1))
done < <(find "${HOME}/Desktop" -maxdepth 1 -name "mac_cleanup_*.log" -type f -print0 \
  | xargs -0 ls -t 2>/dev/null \
  | tail -n +6)
(( log_count > 0 )) && say "Eliminados $log_count logs antiguos."

# --- Resumen Final ---
header "Resumen"
say "Proceso finalizado." "$GREEN"
if (( TOTAL_FREED > 0 )); then
  say "Espacio total liberado: $(format_kb $TOTAL_FREED)" "$CYAN"
else
  if [[ "$MODE" == "dry" ]]; then
    say "Modo dry-run: no se liberó espacio. Usa --run para ejecutar." "$YELLOW"
  else
    say "No se detectó espacio liberado significativo."
  fi
fi
if [[ "$MODE" == "run" ]]; then
  say "Reinicia tu Mac para asegurar estabilidad." "$GREEN"
fi
say "Log guardado en: $LOG"
