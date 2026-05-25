#!/usr/bin/env bash
# lib/constants.sh — Constantes globales del proyecto wlab
# No ejecutar directamente. Cargado por wlab.sh

readonly VER="5.5"

# ── Tiempos de escaneo ─────────────────────────────────────────────────────────
# Los escaneos necesitan tiempo fijo porque airodump escucha pasivamente;
# no existe evento que indique "ya vi todo". Se usa el mínimo razonable.
readonly SCAN_SEC=20          # Escaneo general de APs (segundos)
readonly SCAN_CLIENT_SEC=12   # Escaneo de clientes del AP objetivo (segundos)

# ── Captura de handshake ───────────────────────────────────────────────────────
# NO hay tiempo predefinido de espera: el monitor sale en cuanto detecta
# handshake. CAP_MAX_SEC es únicamente un límite de seguridad antibloqueo
# por si el AP no genera tráfico en absoluto.
readonly CAP_MAX_SEC=90       # Límite de seguridad por intento (segundos)

# ── Deauth ─────────────────────────────────────────────────────────────────────
# DEAUTH_N: paquetes por llamada aireplay-ng. 8 fuerza desconexión fiablemente;
# más paquetes no mejoran el resultado.
readonly DEAUTH_N=8
# DEAUTH_ROUNDS: ciclos de deauth por intento. 2 como red de seguridad;
# en la práctica el handshake llega en la primera ráfaga.
readonly DEAUTH_ROUNDS=2
# Pausa entre rondas: tiempo para que el cliente reautentique y genere 4-way.
readonly DEAUTH_INTERVAL=3

# ── Caché ──────────────────────────────────────────────────────────────────────
readonly META_MAX_AGE=1800    # Validez de caché: 30 minutos
readonly META_DIR="${HOME}/wssids"

# ── Intentos ───────────────────────────────────────────────────────────────────
# Fijo e independiente del número de clientes detectados.
readonly MAX_TRIES_DEFAULT=3

# ── Herramientas opcionales ────────────────────────────────────────────────────
# Detectadas UNA sola vez en preflight() y exportadas aquí.
# output.sh y capture.sh leen estas variables — nunca vuelven a hacer command -v.
HAS_HCXPCAPNGTOOL=""   # "1" si disponible
HAS_CAP2HCCAPX=""      # "1" si disponible
HAS_TSHARK=""          # "1" si disponible

# ── Directorio temporal ────────────────────────────────────────────────────────
readonly TMP=$(mktemp -d /tmp/wlab.XXXXXX)
