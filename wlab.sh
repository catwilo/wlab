#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  wlab.sh  v5.5  ·  WPA2 Handshake Capture — Entry Point                    ║
# ║  Uso:  sudo ./wlab.sh -i <iface> -t <BSSID|SSID> [-t ...] [-c ch] [-o dir] ║
# ║  SOLO PARA REDES PROPIAS O AUTORIZADAS — USO EDUCATIVO / LAB                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Forzar bash aunque se invoque desde zsh
# zsh suspende procesos en background que escriben a tty
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -Eeuo pipefail

# ── Directorio base del proyecto ──────────────────────────────────────────────
WLAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${WLAB_DIR}/lib"

# ── Cargar módulos en orden ────────────────────────────────────────────────────
source "${LIB_DIR}/constants.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/state.sh"
source "${LIB_DIR}/cleanup.sh"
source "${LIB_DIR}/args.sh"
source "${LIB_DIR}/meta.sh"
source "${LIB_DIR}/preflight.sh"
source "${LIB_DIR}/iwd.sh"
source "${LIB_DIR}/monitor.sh"
source "${LIB_DIR}/scan.sh"
source "${LIB_DIR}/clients.sh"
source "${LIB_DIR}/deauth.sh"
source "${LIB_DIR}/capture.sh"
source "${LIB_DIR}/output.sh"

# ── Main ──────────────────────────────────────────────────────────────────────
echo -e "\n${B}${C}  wlab.sh v${VER} — WPA2 Lab Tool${N}  ·  solo redes autorizadas"
echo -e "${DIM}  Shell: ${BASH}  PID: $$${N}\n"

parse_args "$@"

# Fase única: preflight + monitor (se hace UNA sola vez para todos los targets)
preflight
save_and_stop_iwd
start_monitor

# ── Loop multi-target ─────────────────────────────────────────────────────────
total_targets=${#TARGETS_RAW[@]}
echo -e "\n${B}${C}  Targets en esta sesión: ${total_targets}${N}" >&2
for t in "${TARGETS_RAW[@]}"; do echo -e "    ${DIM}→ ${t}${N}" >&2; done
echo "" >&2

target_idx=0
for raw_target in "${TARGETS_RAW[@]}"; do
    target_idx=$(( target_idx + 1 ))

    echo -e "\n${B}${C}════════════════════════════════════════════════════════════════════${N}" >&2
    echo -e "${B}${C}  TARGET ${target_idx}/${total_targets}: ${raw_target}${N}" >&2
    echo -e "${B}${C}════════════════════════════════════════════════════════════════════${N}\n" >&2

    # Limpiar estado del target anterior antes de procesar el siguiente
    _reset_target_state
    TARGET="$raw_target"

    # Inicializar caché para este target
    hdr "Caché de red"
    init_meta
    if load_meta; then
        (( META_LOADED == 1 )) \
            && ok  "Datos frescos — escaneo omitido." \
            || warn "Caché expirada — se usará con verificación ante fallos."
    else
        info "Sin caché para '${TARGET}' — escaneo completo."
    fi

    # Resolver BSSID/canal y capturar handshake
    resolve_target

    if capture; then
        optimize
    else
        # capture() llama die() internamente en la mayoría de casos,
        # pero si en algún flujo retorna 1 sin morir, lo registramos.
        warn "Target ${raw_target}: captura finalizada sin handshake."
        _record_target_failure
    fi
done

# ── Resumen final — siempre el último mensaje del script ──────────────────────
summary
