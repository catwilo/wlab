#!/usr/bin/env bash
# lib/clients.sh — Detección de clientes conectados al AP objetivo
# No ejecutar directamente. Cargado por wlab.sh
#
# DISEÑO IMPORTANTE:
# Se usa SIEMPRE un CSV propio (clients-01.csv) con --bssid y --channel fijos.
# NUNCA se reutiliza el CSV del escaneo general (scan-01.csv), porque ese
# escaneo salta canales y los clientes del AP específico no aparecen o
# aparecen con señal inconsistente.

# CSV dedicado para clientes (separado del escaneo general de redes)
_CLIENTS_CSV="${TMP}/clients-01.csv"

# _scan_clients_fixed: escaneo corto enfocado al AP con canal y BSSID fijos.
# Elimina el CSV anterior para garantizar datos frescos.
_scan_clients_fixed() {
    # Borrar CSV previo para forzar datos frescos
    rm -f "${TMP}/clients-01.csv" 2>/dev/null || true

    info "Escaneando clientes en '${SSID_NAME}' (canal ${CHANNEL}, ${SCAN_CLIENT_SEC}s)..."
    dbg "  airodump-ng --bssid ${TARGET} --channel ${CHANNEL} → ${TMP}/clients"

    # CRÍTICO: --bssid + --channel fijos evita que airodump salte canales.
    # Sin esto, los clientes del AP aparecen esporádicamente o no aparecen.
    airodump-ng \
        --bssid          "$TARGET"   \
        --channel        "$CHANNEL"  \
        --output-format  csv         \
        --write          "${TMP}/clients" \
        "$MON" > "${TMP}/clients_scan.log" 2>&1 &
    local p=$!
    dbg "  airodump-ng clientes PID: ${p}"

    local i=0
    while kill -0 "$p" 2>/dev/null && (( i < SCAN_CLIENT_SEC )); do
        printf "\r  ${C}Buscando clientes... %2ds${N}" "$(( SCAN_CLIENT_SEC - i ))" >&2
        sleep 1; i=$(( i+1 ))
    done
    printf "\r  ${C}Escaneo de clientes completado.   ${N}\n" >&2

    kill "$p" 2>/dev/null || true
    wait "$p" 2>/dev/null || true

    if [[ ! -f "$_CLIENTS_CSV" ]]; then
        warn "No se generó CSV de clientes. Log airodump:"
        while IFS= read -r l; do warn "  $l"; done < "${TMP}/clients_scan.log" 2>/dev/null || true
    fi
}

# _parse_clients_from_csv: lee el CSV y extrae clientes del AP TARGET.
# $1 = ruta al CSV
# Imprime tabla a stderr, devuelve conteo a stdout.
_parse_clients_from_csv() {
    local csv="$1"
    [[ ! -f "$csv" ]] && { echo "0"; return; }

    # Tabla de clientes detectados → stderr
    local table
    table=$(awk -F',' -v ap="${TARGET^^}" '
        /^[[:space:]]*$/ { past=1; next }
        past && /^[0-9A-Fa-f]{2}:/ {
            for(i=1;i<=NF;i++) gsub(/^ +| +$/,"",$i)
            if (toupper($6)==ap)
                printf "    MAC=%-20s  AP=%-20s  Señal=%s dBm\n",$1,$6,$4
        }' "$csv" 2>/dev/null) || true

    if [[ -n "$table" ]]; then
        dbg "Clientes detectados para AP ${TARGET}:"
        echo "$table" >&2
    else
        dbg "Ningún cliente en la sección de clientes del CSV para AP ${TARGET}"
        dbg "  (CSV: ${csv})"
    fi

    # Conteo → stdout (único valor numérico)
    awk -F',' -v ap="${TARGET^^}" '
        /^[[:space:]]*$/ { past=1; next }
        past && /^[0-9A-Fa-f]{2}:/ {
            for(i=1;i<=NF;i++) gsub(/^ +| +$/,"",$i)
            if (toupper($6)==ap) count++
        }
        END { print count+0 }' "$csv" 2>/dev/null || echo "0"
}

# detect_clients: escanea y reporta clientes. Siempre hace escaneo fresco
# con canal fijo para garantizar detección correcta.
# Imprime a stdout SOLO el número entero de clientes.
detect_clients() {
    _scan_clients_fixed

    local n
    n=$(_parse_clients_from_csv "$_CLIENTS_CSV")

    # Validar que sea número
    if [[ ! "$n" =~ ^[0-9]+$ ]]; then
        warn "Conteo de clientes inválido: '${n}' — asumiendo 0"
        n=0
    fi

    echo "$n"
}

# get_client_macs: devuelve MACs de clientes del AP (una por línea, a stdout).
# Lee del CSV de clientes dedicado generado por detect_clients.
get_client_macs() {
    [[ ! -f "$_CLIENTS_CSV" ]] && return 0

    awk -F',' -v ap="${TARGET^^}" '
        /^[[:space:]]*$/ { past=1; next }
        past && /^[0-9A-Fa-f]{2}:/ {
            for(i=1;i<=NF;i++) gsub(/^ +| +$/,"",$i)
            if (toupper($6)==ap) print toupper($1)
        }' "$_CLIENTS_CSV" 2>/dev/null || true
}
