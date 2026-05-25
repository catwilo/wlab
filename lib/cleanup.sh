#!/usr/bin/env bash
# lib/cleanup.sh — Limpieza de recursos y restauración del sistema
# No ejecutar directamente. Cargado por wlab.sh

cleanup() {
    local rc=$?
    echo "" >&2
    warn "Ejecutando cleanup..."

    # Matar procesos de captura/deauth si siguen corriendo
    pkill -9 -f "airodump-ng|aireplay-ng" 2>/dev/null || true
    sleep 1

    # Detener interfaz monitor
    if [[ -n "$MON" ]]; then
        dbg "Deteniendo monitor: $MON"
        airmon-ng stop "$MON" 2>&1 \
            | while IFS= read -r l; do dbg "  $l"; done || true
    fi

    # Restaurar iwd si estaba activo
    if [[ $IWD_WAS_UP -eq 1 ]]; then
        info "Restaurando iwd..."
        systemctl unmask iwd 2>/dev/null || true
        systemctl enable iwd 2>/dev/null || true
        systemctl start  iwd 2>/dev/null || true
        sleep 3

        if [[ -n "$IWD_NET" ]]; then
            info "Reconectando a '${IWD_NET}'..."
            local w=0
            until iwctl station "$IFACE" show &>/dev/null || (( w >= 15 )); do
                printf "\r  Esperando iwd... %ds" "$w" >&2
                sleep 1; w=$(( w+1 ))
            done
            echo "" >&2
            iwctl station "$IFACE" connect "$IWD_NET" 2>/dev/null || true
            sleep 5

            if iwctl station "$IFACE" show 2>/dev/null | grep -qi "connected"; then
                ok "Reconectado a '${IWD_NET}'."
            else
                warn "Reconexión falló. Ejecuta manualmente:"
                warn "  sudo iwctl station ${IFACE} connect '${IWD_NET}'"
            fi
        fi
    fi

    # Limpiar temporales
    rm -rf "$TMP"
    [[ $rc -eq 0 ]] \
        && ok  "Finalizado OK (rc=0)." \
        || warn "Finalizado con errores (rc=${rc})."
}

trap cleanup EXIT
trap 'warn "Señal INT/TERM recibida."; exit 130' INT TERM
