#!/usr/bin/env bash
# lib/scan.sh — Escaneo de redes y resolución de BSSID/Canal desde SSID
# No ejecutar directamente. Cargado por wlab.sh

run_scan() {
    local duration="${1:-$SCAN_SEC}"
    rm -f "${TMP}/scan-01.csv" 2>/dev/null || true
    info "Escaneo de redes (${duration}s) → ${TMP}/scan.log"

    # Redirigir stdout+stderr a archivo — evita suspend en zsh y permite captura real
    airodump-ng \
        --output-format csv \
        --write "${TMP}/scan" \
        "$MON" > "${TMP}/scan.log" 2>&1 &
    local scan_pid=$!
    dbg "airodump-ng escaneo PID: ${scan_pid}"

    local i=0
    while kill -0 "$scan_pid" 2>/dev/null && (( i < duration )); do
        printf "\r  ${C}Escaneando... %2ds${N}" "$(( duration - i ))" >&2
        sleep 1; i=$(( i+1 ))
    done
    printf "\r  ${C}Escaneo completado.       ${N}\n" >&2

    kill "$scan_pid" 2>/dev/null || true
    wait "$scan_pid" 2>/dev/null || true

    if [[ ! -f "${TMP}/scan-01.csv" ]]; then
        warn "Log airodump-ng (escaneo):"
        while IFS= read -r l; do warn "  $l"; done < "${TMP}/scan.log" 2>/dev/null || true
        die "Sin CSV tras escaneo. ¿${MON} en monitor mode y UP?"
    fi

    local ap_count
    ap_count=$(grep -c '^[0-9A-Fa-f]\{2\}:' "${TMP}/scan-01.csv" 2>/dev/null || echo 0)
    dbg "APs detectados en CSV: ${ap_count}"

    if [[ "$ap_count" -eq 0 ]]; then
        warn "CSV vacío. Log airodump-ng:"
        while IFS= read -r l; do warn "  $l"; done < "${TMP}/scan.log" 2>/dev/null || true
        die "Escaneo sin resultados. ¿Interfaz en monitor mode?"
    fi
}

resolve_target() {
    hdr "Resolución de objetivo"

    local is_bssid=0
    [[ "$TARGET" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] && is_bssid=1
    dbg "TARGET='${TARGET}'  is_bssid=${is_bssid}  META_LOADED=${META_LOADED}  CHANNEL='${CHANNEL}'"

    # Caché válida — no hace falta escanear
    if (( META_LOADED >= 1 )) && [[ -n "$CHANNEL" ]]; then
        TARGET="${TARGET^^}"
        local src="caché fresca"
        (( META_LOADED == 2 )) && src="caché expirada"
        ok "BSSID=${TARGET}  Canal=${CHANNEL}  SSID='${SSID_NAME}'  (${src})"
        return 0
    fi

    # BSSID y canal dados directamente por argumento
    if (( is_bssid )) && [[ -n "$CHANNEL" ]]; then
        TARGET="${TARGET^^}"
        [[ -z "$SSID_NAME" ]] && SSID_NAME="$TARGET"
        ok "BSSID=${TARGET}  Canal=${CHANNEL}  (argumentos directos)"
        update_meta_name; write_meta; return 0
    fi

    # Necesita escanear
    run_scan
    local csv="${TMP}/scan-01.csv"

    if (( is_bssid )); then
        # Buscar canal por BSSID
        CHANNEL=$(awk -F',' -v b="${TARGET^^}" '
            /^[0-9A-Fa-f]{2}:/ {
                gsub(/ /,"",$1); gsub(/ /,"",$4)
                if (toupper($1)==b) { print $4; exit }
            }' "$csv")
        [[ -z "$CHANNEL" ]] && die "Canal no encontrado para ${TARGET}. Usa -c <canal>."

        local ssid_found
        ssid_found=$(awk -F',' -v b="${TARGET^^}" '
            /^[0-9A-Fa-f]{2}:/ {
                for(i=1;i<=NF;i++) gsub(/^ +| +$/,"",$i)
                if (toupper($1)==b && $14!="") { print $14; exit }
            }' "$csv") || true
        SSID_NAME="${ssid_found:-$TARGET}"

    else
        # Buscar BSSID+canal por nombre de SSID
        dbg "Buscando SSID '${TARGET}' en CSV..."
        local row
        row=$(awk -F',' -v s="$TARGET" '
            /^[0-9A-Fa-f]{2}:/ {
                for(i=1;i<=NF;i++) gsub(/^ +| +$/,"",$i)
                if ($14==s && $6~/WPA/) { print $1"|"$4; exit }
            }' "$csv") || true

        if [[ -z "$row" ]]; then
            warn "SSID '${TARGET}' no encontrado. Redes detectadas:"
            awk -F',' '/^[0-9A-Fa-f]{2}:/{
                for(i=1;i<=NF;i++) gsub(/^ +| +$/,"",$i)
                if($14!="" && $14!="ESSID")
                    printf "  BSSID=%-20s  Ch=%-3s  Enc=%-10s  SSID=%s\n",$1,$4,$6,$14
            }' "$csv" | head -20 >&2
            die "SSID '${TARGET}' no encontrado en el escaneo."
        fi

        SSID_NAME="$TARGET"
        TARGET=$(cut -d'|' -f1 <<< "$row")
        CHANNEL=${CHANNEL:-$(cut -d'|' -f2 <<< "$row")}
        dbg "Resuelto: BSSID=${TARGET}  CHANNEL=${CHANNEL}"
    fi

    TARGET="${TARGET^^}"
    update_meta_name
    ok "BSSID=${TARGET}  Canal=${CHANNEL}  SSID='${SSID_NAME}'"
    write_meta
}
