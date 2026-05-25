#!/usr/bin/env bash
# lib/monitor.sh — Activación del modo monitor en la interfaz Wi-Fi
# No ejecutar directamente. Cargado por wlab.sh

start_monitor() {
    hdr "Monitor Mode"

    # Matar procesos que interfieren
    info "Matando procesos interferentes (dhcpcd, wpa_supplicant)..."
    pkill -x dhcpcd         2>/dev/null \
        && dbg "dhcpcd terminado."         || dbg "dhcpcd no corría."
    pkill -x wpa_supplicant 2>/dev/null \
        && dbg "wpa_supplicant terminado." || dbg "wpa_supplicant no corría."
    sleep 1

    # airmon-ng check kill con respuesta automática al prompt interactivo
    info "airmon-ng check kill (respuesta automática a prompts)..."
    echo "y" | airmon-ng check kill 2>&1 \
        | while IFS= read -r l; do dbg "  $l"; done || true
    sleep 1

    # Segunda pasada para asegurar limpieza completa
    pkill -9 iwd    2>/dev/null || true
    pkill -9 dhcpcd 2>/dev/null || true
    sleep 1

    # Activar modo monitor
    info "Activando modo monitor en '${IFACE}'..."
    local airmon_out
    airmon_out=$(echo "y" | airmon-ng start "$IFACE" 2>&1) || true
    echo "$airmon_out" | while IFS= read -r l; do dbg "  airmon: $l"; done

    # Detectar nombre de la interfaz monitor creada
    MON=$(echo "$airmon_out" \
        | sed -n 's/.*\]\(wlan[0-9]*mon\).*/\1/p' \
        | head -1)

    # Fallback: buscar con iw dev si airmon no reportó el nombre
    if [[ -z "$MON" ]]; then
        MON=$(iw dev 2>/dev/null \
            | awk '/Interface/{i=$2} /type monitor/{print i}' \
            | head -1)
        [[ -n "$MON" ]] \
            && dbg "Interfaz monitor detectada por fallback (iw dev): '${MON}'" \
            || die "No se creó interfaz monitor.\n  Verifica: sudo iw dev\n  Salida airmon-ng:\n${airmon_out}"
    else
        dbg "Interfaz monitor desde airmon output: '${MON}'"
    fi

    # Asegurar que la interfaz esté UP
    ip link set "$MON" up 2>/dev/null \
        && dbg "${MON} levantado con 'ip link set up'." || true
    sleep 1

    # Verificar estado final
    dbg "Estado final de ${MON}:"
    iw dev "$MON" info 2>/dev/null \
        | while IFS= read -r l; do dbg "  $l"; done || true

    ok "Interfaz monitor activa: ${MON}"
}
