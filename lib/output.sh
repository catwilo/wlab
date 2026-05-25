#!/usr/bin/env bash
# lib/output.sh — Guardado, conversión y resumen de archivos capturados
# No ejecutar directamente. Cargado por wlab.sh
#
# NOMBRES DE ARCHIVO:
#   Formato: <ssid_normalizado>_<MAC con guiones AA-BB-CC-DD-EE-FF>
#   Ejemplo: cursed_1A-7F-7A-6C-91-AB.cap
#            cursed_1A-7F-7A-6C-91-AB.22000
#            cursed_1A-7F-7A-6C-91-AB.info
#
#   El SSID va primero (identificador humano). La MAC con guiones garantiza
#   unicidad y es legible. Si SSID_NAME está vacío → solo la MAC con guiones.
#
# CONVERSIÓN (prioridad):
#   1. hcxpcapngtool → .22000  (hashcat moderno, formato óptimo)
#   2. cap2hccapx    → .hccapx (hashcat legacy, fallback)
#   3. Solo .cap limpio si ninguno disponible
#   Siempre se guarda el .cap limpio además del formato de hashcat.
#
# HAS_HCXPCAPNGTOOL / HAS_CAP2HCCAPX: detectados en preflight(), no aquí.

# _build_basename: construye el prefijo único de nombre de archivo.
# Formato: <ssid_normalizado>_<AA-BB-CC-DD-EE-FF>
_build_basename() {
    local mac_dash
    mac_dash=$(echo "$TARGET" | tr ':' '-' | tr '[:lower:]' '[:upper:]')

    local ssid_norm
    ssid_norm=$(sanitize_name "${SSID_NAME}")   # de meta.sh

    if [[ -n "$ssid_norm" ]]; then
        echo "${ssid_norm}_${mac_dash}"
    else
        echo "${mac_dash}"
    fi
}

# optimize: limpia el .cap y genera los formatos de salida.
# Al terminar registra el resultado en SESSION_RESULTS para el resumen final.
optimize() {
    hdr "Guardando capturas — ${SSID_NAME:-$TARGET}"

    local fname
    fname=$(_build_basename)
    local base="${OUTDIR}/${fname}"
    local clean="${TMP}/${fname}_clean.cap"

    dbg "Nombre base: ${fname}"

    # ── wpaclean: eliminar frames no relevantes ────────────────────────────────
    info "Limpiando captura con wpaclean..."
    if wpaclean "$clean" "$CAP_FILE" > "${TMP}/wpaclean.log" 2>&1 && [[ -s "$clean" ]]; then
        ok "wpaclean OK ($(du -sh "$clean" | cut -f1))"
    else
        warn "wpaclean falló o produjo vacío — usando .cap original sin limpiar."
        dbg "Log wpaclean:"
        while IFS= read -r l; do dbg "  wpaclean: $l"; done < "${TMP}/wpaclean.log" || true
        cp "$CAP_FILE" "$clean"
    fi

    # Siempre guardar el .cap limpio
    cp "$clean" "${base}.cap"
    ok "→ ${base}.cap  (pcap limpio)"

    local best_format=""

    # ── hcxpcapngtool → .22000 ────────────────────────────────────────────────
    if [[ -n "$HAS_HCXPCAPNGTOOL" ]]; then
        if hcxpcapngtool -o "${base}.22000" "$clean" > "${TMP}/hcxpcap.log" 2>&1 \
                && [[ -s "${base}.22000" ]]; then
            ok "→ ${base}.22000  (hashcat WPA2 moderno — formato óptimo)"
            best_format="22000"
        else
            warn "hcxpcapngtool disponible pero falló al convertir."
            dbg "Log hcxpcapngtool:"
            while IFS= read -r l; do dbg "  hcxpcapngtool: $l"; done \
                < "${TMP}/hcxpcap.log" || true
        fi
    fi

    # ── cap2hccapx → .hccapx (fallback) ──────────────────────────────────────
    if [[ -z "$best_format" && -n "$HAS_CAP2HCCAPX" ]]; then
        if cap2hccapx "$clean" "${base}.hccapx" > "${TMP}/cap2hccapx.log" 2>&1 \
                && [[ -s "${base}.hccapx" ]]; then
            ok "→ ${base}.hccapx  (hashcat legacy)"
            best_format="hccapx"
        else
            warn "cap2hccapx disponible pero falló al convertir."
            while IFS= read -r l; do dbg "  cap2hccapx: $l"; done \
                < "${TMP}/cap2hccapx.log" || true
        fi
    fi

    [[ -z "$best_format" ]] && dbg "Sin formato hashcat generado — solo .cap disponible."

    # ── .info: metadatos de sesión ─────────────────────────────────────────────
    {
        printf "# wlab v%s  %s\n" "$VER" "$(date '+%Y-%m-%d %H:%M:%S')"
        printf "SSID=%s\nBSSID=%s\nChannel=%s\nIface=%s\nMonitor=%s\n" \
            "$SSID_NAME" "$TARGET" "$CHANNEL" "$IFACE" "$MON"
    } > "${base}.info"
    ok "→ ${base}.info"

    # ── Registrar resultado en SESSION_RESULTS para el resumen final ──────────
    local hs_status="ok"
    local hs_count=0 eapol=0
    local ac_out
    ac_out=$(aircrack-ng "${base}.cap" 2>/dev/null || true)
    local fi
    fi=$(echo "$ac_out" | grep -oE '[0-9]+ handshake' | head -1) || true
    [[ -n "$fi" ]] && hs_count=$(echo "$fi" | grep -oE '^[0-9]+') || hs_count=0
    [[ -n "$HAS_TSHARK" ]] \
        && eapol=$(tshark -r "${base}.cap" -Y "eapol" -T fields \
            -e frame.number 2>/dev/null | wc -l) || true

    if (( hs_count > 0 ));    then hs_status="completo"
    elif (( eapol >= 2 ));    then hs_status="parcial"
    else                           hs_status="sin_handshake"
    fi

    # Formato: "SSID|BSSID|Canal|status|hs_count|eapol|fname"
    SESSION_RESULTS+=("${SSID_NAME}|${TARGET}|${CHANNEL}|${hs_status}|${hs_count}|${eapol}|${fname}")

    sep
}

# _record_target_failure: registra en SESSION_RESULTS cuando no hubo captura.
# Llamado desde el loop multi-target de wlab.sh al fallar capture().
_record_target_failure() {
    local label="${SSID_NAME:-${TARGET}}"
    SESSION_RESULTS+=("${label}|${TARGET}|${CHANNEL:-?}|fallido|0|0|—")
}

# summary: resumen final consolidado de TODOS los targets de la sesión.
# Siempre es el último mensaje del script (llamado desde wlab.sh).
summary() {
    local total=${#SESSION_RESULTS[@]}

    echo "" >&2
    echo -e "${B}${C}╔══════════════════════════════════════════════════════════════════════╗${N}" >&2
    echo -e "${B}${C}║                     RESUMEN DE SESIÓN wlab v${VER}                     ║${N}" >&2
    echo -e "${B}${C}╚══════════════════════════════════════════════════════════════════════╝${N}" >&2
    echo "" >&2

    echo -e "  ${B}Interfaz${N}  : ${C}${IFACE}${N}  →  monitor ${C}${MON}${N}" >&2
    echo -e "  ${B}Targets procesados${N}: ${total}" >&2
    echo "" >&2

    local ok_count=0 partial_count=0 fail_count=0

    local idx=0
    for entry in "${SESSION_RESULTS[@]}"; do
        idx=$(( idx + 1 ))
        IFS='|' read -r s_ssid s_bssid s_ch s_status s_hs s_eapol s_fname <<< "$entry"

        echo -e "  ${B}── Target ${idx}/${total}${N}" >&2
        echo -e "    SSID    : ${C}${s_ssid}${N}" >&2
        echo -e "    BSSID   : ${C}${s_bssid}${N}" >&2
        echo -e "    Canal   : ${C}${s_ch}${N}" >&2

        case "$s_status" in
            completo)
                echo -e "    Estado  : ${G}✔  Handshake COMPLETO${N}  (aircrack: ${s_hs} | EAPOL: ${s_eapol} frames)" >&2
                echo -e "    ${G}✔  Listo para brute-force${N}" >&2
                ok_count=$(( ok_count + 1 ))
                ;;
            parcial)
                echo -e "    Estado  : ${Y}⚠  Handshake PARCIAL${N}  (EAPOL frames: ${s_eapol} — puede ser suficiente)" >&2
                partial_count=$(( partial_count + 1 ))
                ;;
            fallido)
                echo -e "    Estado  : ${R}✘  Sin handshake capturado${N}" >&2
                echo -e "    ${Y}Causas posibles: sin clientes activos, señal débil, PMF/MFP activo.${N}" >&2
                fail_count=$(( fail_count + 1 ))
                ;;
            sin_handshake)
                echo -e "    Estado  : ${R}✘  Archivos generados pero sin handshake válido${N}" >&2
                fail_count=$(( fail_count + 1 ))
                ;;
        esac

        # Archivos generados (si hay nombre de archivo real)
        if [[ "$s_fname" != "—" ]]; then
            local base="${OUTDIR}/${s_fname}"
            echo -e "    ${B}Archivos${N}:" >&2
            for ext in cap 22000 hccapx info; do
                local f="${base}.${ext}"
                if [[ -f "$f" && -s "$f" ]]; then
                    local sz; sz=$(du -sh "$f" | cut -f1)
                    local lbl=""
                    case "$ext" in
                        cap)    lbl="pcap — aircrack-ng / hashcat" ;;
                        22000)  lbl="hashcat -m 22000  ✦ RECOMENDADO" ;;
                        hccapx) lbl="hashcat -m 2500" ;;
                        info)   lbl="metadatos" ;;
                    esac
                    echo -e "      ${G}✔${N}  ${s_fname}.${ext}  (${sz})  — ${lbl}" >&2
                fi
            done

            # Comandos de uso
            echo -e "    ${B}Uso${N}:" >&2
            [[ -f "${base}.22000"  ]] && echo -e "      ${C}hashcat -m 22000 ${base}.22000 wordlist.txt${N}" >&2
            [[ -f "${base}.hccapx" ]] && echo -e "      ${C}hashcat -m 2500  ${base}.hccapx wordlist.txt${N}" >&2
            echo -e "      ${C}aircrack-ng -w wordlist.txt ${base}.cap${N}" >&2
        fi

        echo "" >&2
    done

    # ── Totales ───────────────────────────────────────────────────────────────
    echo -e "  ${B}Totales${N}" >&2
    echo -e "    ${G}✔  Handshake completo  : ${ok_count}${N}" >&2
    echo -e "    ${Y}⚠  Handshake parcial   : ${partial_count}${N}" >&2
    echo -e "    ${R}✘  Sin handshake       : ${fail_count}${N}" >&2
    echo "" >&2

    # ── Caché ─────────────────────────────────────────────────────────────────
    echo -e "  ${B}Caché${N}" >&2
    [[ -n "$META_FILE" ]] && echo -e "    Última red  : ${META_FILE}" >&2
    echo -e "    Todas       : ls ${META_DIR}/" >&2

    if [[ -z "$HAS_HCXPCAPNGTOOL" && -z "$HAS_CAP2HCCAPX" ]]; then
        echo "" >&2
        echo -e "    ${Y}Para generar formato hashcat: sudo apt install hcxtools${N}" >&2
    fi

    echo "" >&2
    echo -e "${B}${C}══════════════════════════════════════════════════════════════════════${N}" >&2
    echo "" >&2
}
