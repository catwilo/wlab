#!/usr/bin/env bash
# lib/state.sh — Variables de estado global (mutables durante ejecución)
# No ejecutar directamente. Cargado por wlab.sh

IFACE=""          # Interfaz física (ej: wlan0)
TARGET=""         # BSSID objetivo activo (siempre en mayúsculas tras resolve)
SSID_NAME=""      # SSID legible de la red activa
CHANNEL=""        # Canal Wi-Fi del AP activo
OUTDIR="$(pwd)"   # Directorio de salida para archivos capturados

MON=""            # Nombre de la interfaz en modo monitor (ej: wlan0mon)
CAP_FILE=""       # Ruta al .cap con el handshake capturado
IWD_WAS_UP=0      # 1 si iwd estaba activo antes de iniciar
IWD_NET=""        # SSID al que iwd estaba conectado

META_FILE=""      # Ruta al archivo .meta de caché
META_LOADED=0     # 0=sin caché  1=caché fresca  2=caché expirada

# ── Multi-target ──────────────────────────────────────────────────────────────
# TARGETS_RAW: lista cruda de -t recibidos (llenada por args.sh)
# SESSION_RESULTS: acumula resultados por target para el resumen final
declare -a TARGETS_RAW=()
declare -a SESSION_RESULTS=()   # cada entrada: "SSID|BSSID|Canal|status|archivo"

# _reset_target_state: limpia estado por-target antes de procesar el siguiente.
# NO toca IFACE, MON, OUTDIR, IWD_*, ni SESSION_RESULTS.
_reset_target_state() {
    TARGET=""
    SSID_NAME=""
    CHANNEL=""
    CAP_FILE=""
    META_FILE=""
    META_LOADED=0
}
