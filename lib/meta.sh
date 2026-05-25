#!/usr/bin/env bash
# lib/meta.sh — Caché de metadatos de redes escaneadas
# No ejecutar directamente. Cargado por wlab.sh

sanitize_name() {
    echo "$1" | tr '[:upper:]' '[:lower:]' \
        | tr -cs 'a-z0-9._-' '_' \
        | sed 's/_\+/_/g; s/^_//; s/_$//'
}

init_meta() {
    if [[ ! -d "$META_DIR" ]]; then
        mkdir -p "$META_DIR" || die "No se pudo crear META_DIR: ${META_DIR}"
        chmod 700 "$META_DIR" 2>/dev/null || true
        ok "Directorio de metadatos creado: ${META_DIR}"
    else
        dbg "META_DIR existe: ${META_DIR}"
    fi
    META_FILE="${META_DIR}/$(sanitize_name "$TARGET").meta"
    dbg "META_FILE provisional: ${META_FILE}"
}

update_meta_name() {
    [[ -z "$SSID_NAME" ]] && return 0
    local new="${META_DIR}/$(sanitize_name "$SSID_NAME").meta"
    if [[ "$new" != "$META_FILE" && -f "$META_FILE" ]]; then
        mv -f "$META_FILE" "$new" 2>/dev/null || true
        dbg "META_FILE renombrado → ${new}"
    fi
    META_FILE="$new"
}

write_meta() {
    [[ -z "$META_FILE" ]] && return 0
    mkdir -p "$META_DIR" 2>/dev/null || true
    cat > "$META_FILE" <<EOF
# wlab.sh v${VER} — Caché de metadatos. No editar manualmente.
WLAB_VERSION=${VER}
TIMESTAMP=$(date '+%s')
DATETIME=$(date '+%Y-%m-%d %H:%M:%S')
SSID=${SSID_NAME}
BSSID=${TARGET}
CHANNEL=${CHANNEL}
IFACE=${IFACE}
OUTDIR=${OUTDIR}
IWD_WAS_UP=${IWD_WAS_UP}
IWD_NET=${IWD_NET}
HOSTNAME=$(hostname 2>/dev/null || echo unknown)
KERNEL=$(uname -r   2>/dev/null || echo unknown)
EOF
    chmod 600 "$META_FILE" 2>/dev/null || true
    ok "Metadatos guardados → ${META_FILE}"
}

load_meta() {
    [[ -z "$META_FILE" || ! -f "$META_FILE" ]] && {
        dbg "Sin META_FILE o archivo no existe."
        return 1
    }

    local ts bssid channel ssid_stored
    ts=$(         grep '^TIMESTAMP=' "$META_FILE" | cut -d'=' -f2- | tr -d '[:space:]') \
        || { rm -f "$META_FILE"; return 1; }
    bssid=$(      grep '^BSSID='     "$META_FILE" | cut -d'=' -f2- | tr -d '[:space:]') \
        || { rm -f "$META_FILE"; return 1; }
    channel=$(    grep '^CHANNEL='   "$META_FILE" | cut -d'=' -f2- | tr -d '[:space:]') \
        || { rm -f "$META_FILE"; return 1; }
    ssid_stored=$(grep '^SSID='      "$META_FILE" | cut -d'=' -f2-) \
        || { rm -f "$META_FILE"; return 1; }

    # Validaciones de integridad
    if [[ -z "$ts" || -z "$bssid" || -z "$channel" ]]; then
        warn "Caché corrupta (campos vacíos) — descartando."
        rm -f "$META_FILE"; return 1
    fi
    if [[ ! "$ts"      =~ ^[0-9]+$ ]]; then
        warn "Caché corrupta (timestamp inválido) — descartando."
        rm -f "$META_FILE"; return 1
    fi
    if [[ ! "$bssid"   =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        warn "Caché corrupta (BSSID inválido) — descartando."
        rm -f "$META_FILE"; return 1
    fi
    if [[ ! "$channel" =~ ^[0-9]+$ ]]; then
        warn "Caché corrupta (canal inválido) — descartando."
        rm -f "$META_FILE"; return 1
    fi

    local now age mins secs
    now=$(date '+%s')
    age=$(( now - ts ))
    mins=$(( age / 60 ))
    secs=$(( age % 60 ))

    TARGET="$bssid"
    CHANNEL="$channel"
    SSID_NAME="${ssid_stored}"
    update_meta_name

    if (( age > META_MAX_AGE )); then
        warn "Caché de '${ssid_stored}' expirada (${mins}m ${secs}s)."
        META_LOADED=2
    else
        ok "Caché válida '${ssid_stored}' (${mins}m ${secs}s) — escaneo omitido."
        META_LOADED=1
    fi
    return 0
}
