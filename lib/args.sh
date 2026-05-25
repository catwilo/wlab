#!/usr/bin/env bash
# lib/args.sh — Parseo de argumentos de línea de comandos
# No ejecutar directamente. Cargado por wlab.sh

usage() {
    echo -e "${B}wlab.sh v${VER}${N} — WPA2 Lab Tool (solo redes autorizadas)" >&2
    echo -e "  sudo wlab.sh -i <iface> -t <BSSID|SSID> [-t <BSSID|SSID> ...] [-c <canal>] [-o <dir>]\\n" >&2
    echo "  -i  Interfaz física    (ej: wlan0)" >&2
    echo "  -t  BSSID o SSID       (repetible — uno por red objetivo)" >&2
    echo "  -c  Canal              (opcional — se autodetecta por escaneo)" >&2
    echo "  -o  Directorio salida  (por defecto: directorio actual)" >&2
    echo "  -h  Esta ayuda" >&2
    echo "" >&2
    echo "  Ejemplos:" >&2
    echo "    sudo wlab.sh -i wlan0 -t MiRed" >&2
    echo "    sudo wlab.sh -i wlan0 -t MiRed -t AA:BB:CC:DD:EE:FF -t OtraRed" >&2
    exit 0
}

parse_args() {
    [[ $# -eq 0 ]] && usage

    # TARGETS_RAW acumula cada -t recibido (array global, definido en state.sh)
    while getopts ":i:t:c:o:h" opt; do
        case $opt in
            i) IFACE="$OPTARG"                ;;
            t) TARGETS_RAW+=("$OPTARG")       ;;
            c) CHANNEL="$OPTARG"              ;;
            o) OUTDIR="$OPTARG"               ;;
            h) usage                          ;;
            :) die "La opción -${OPTARG} requiere un argumento." ;;
            *) die "Opción desconocida: -${OPTARG}  (usa -h para ayuda)" ;;
        esac
    done

    [[ -z "$IFACE" ]]                && die "Falta argumento obligatorio: -i <interfaz>"
    [[ ${#TARGETS_RAW[@]} -eq 0 ]]  && die "Falta argumento obligatorio: -t <BSSID|SSID>"
    [[ -n "$CHANNEL" && ! "$CHANNEL" =~ ^[0-9]+$ ]] \
        && die "El canal (-c) debe ser un número entero positivo."
    mkdir -p "$OUTDIR" \
        || die "No se pudo crear el directorio de salida: ${OUTDIR}"

    dbg "Args parseados: IFACE=${IFACE} TARGETS=(${TARGETS_RAW[*]}) CHANNEL=${CHANNEL:-auto} OUTDIR=${OUTDIR}"
}
