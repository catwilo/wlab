#!/usr/bin/env bash
# lib/logging.sh — Funciones de logging y color
# No ejecutar directamente. Cargado por wlab.sh

# Colores ANSI
R='\033[0;31m'   # Rojo
G='\033[0;32m'   # Verde
Y='\033[1;33m'   # Amarillo
C='\033[0;36m'   # Cyan
B='\033[1m'      # Negrita
N='\033[0m'      # Reset
DIM='\033[2m'    # Tenue

# CRÍTICO: todas las funciones de logging escriben a stderr (>&2)
# Esto evita que los mensajes dbg contaminen capturas de variables $(...)

ts()   { date '+%H:%M:%S'; }
info() { echo -e "${C}[·]${N} $(ts) $*" >&2; }
ok()   { echo -e "${G}[✔]${N} $(ts) $*" >&2; }
warn() { echo -e "${Y}[!]${N} $(ts) $*" >&2; }
hdr()  { echo -e "\n${B}${C}── $* ──${N}" >&2; }
sep()  { echo -e "${DIM}$(printf '─%.0s' {1..76})${N}" >&2; }
die()  { echo -e "\n${R}[✘] $(ts) $*${N}" >&2; exit 1; }
dbg()  { echo -e "${DIM}    [dbg] $(ts) $*${N}" >&2; }
