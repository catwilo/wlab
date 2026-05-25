#!/usr/bin/env bash
# lib/iwd.sh — Gestión del daemon iwd (detener antes de capturar, restaurar al final)
# No ejecutar directamente. Cargado por wlab.sh

save_and_stop_iwd() {
    hdr "Gestión iwd"

    if systemctl is-active --quiet iwd 2>/dev/null; then
        IWD_WAS_UP=1

        # Guardar red conectada actual para reconectar al terminar
        IWD_NET=$(iwctl station "$IFACE" show 2>/dev/null \
            | awk '/Connected network/ {print $NF}' \
            | tr -d '[:space:]') || true

        if [[ -n "$IWD_NET" ]]; then
            ok "Red guardada para restaurar: '${IWD_NET}'"
        else
            warn "iwd activo pero sin red conectada actualmente."
        fi

        # Detener y enmascarar para que no interfiera con airmon-ng
        systemctl stop iwd 2>&1 \
            | while IFS= read -r l; do dbg "  stop: $l"; done || true
        systemctl mask iwd 2>&1 \
            | while IFS= read -r l; do dbg "  mask: $l"; done || true

        # Matar procesos residuales
        pkill -9 iwd    2>/dev/null || true
        pkill -9 dhcpcd 2>/dev/null || true
        sleep 2

        ok "iwd detenido y enmascarado correctamente."
    else
        warn "iwd no estaba activo — nada que detener."
    fi
}
