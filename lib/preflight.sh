#!/usr/bin/env bash
# lib/preflight.sh — Verificaciones previas al inicio
# No ejecutar directamente. Cargado por wlab.sh

preflight() {
    hdr "Pre-flight"

    [[ $(id -u) -eq 0 ]] || die "Este script requiere privilegios root: sudo ./wlab.sh ..."
    ok "Root: OK"

    # ── Dependencias obligatorias ──────────────────────────────────────────────
    local miss=()
    for dep in airmon-ng airodump-ng aireplay-ng aircrack-ng wpaclean iwctl; do
        if command -v "$dep" &>/dev/null; then
            dbg "  dep OK: $dep → $(command -v "$dep")"
        else
            miss+=("$dep")
        fi
    done
    (( ${#miss[@]} > 0 )) \
        && die "Dependencias faltantes: ${miss[*]}\n  → sudo apt install aircrack-ng iwd"
    ok "Dependencias obligatorias: OK"

    # ── Herramientas opcionales ────────────────────────────────────────────────
    # Resultado guardado en HAS_* — única detección en todo el script.
    # output.sh y capture.sh usan estas variables directamente.
    local any_missing=0
    for opt in hcxpcapngtool cap2hccapx tshark; do
        if command -v "$opt" &>/dev/null; then
            dbg "  opcional OK: $opt → $(command -v "$opt")"
            case "$opt" in
                hcxpcapngtool) HAS_HCXPCAPNGTOOL=1 ;;
                cap2hccapx)    HAS_CAP2HCCAPX=1    ;;
                tshark)        HAS_TSHARK=1         ;;
            esac
        else
            dbg "  opcional ausente: $opt"
            any_missing=1
            case "$opt" in
                hcxpcapngtool|cap2hccapx)
                    warn "Herramienta opcional no encontrada: $opt  (instalar: sudo apt install hcxtools)" ;;
                tshark)
                    warn "Herramienta opcional no encontrada: tshark  (instalar: sudo apt install tshark)" ;;
            esac
        fi
    done

    dbg "HAS_HCXPCAPNGTOOL=${HAS_HCXPCAPNGTOOL}  HAS_CAP2HCCAPX=${HAS_CAP2HCCAPX}  HAS_TSHARK=${HAS_TSHARK}"
    dbg "Shell: ${BASH}  versión: ${BASH_VERSION}"
    dbg "Sistema: $(uname -a)"
    sep
}
