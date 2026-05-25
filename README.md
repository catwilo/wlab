# wlab — WPA2 Handshake Capture Tool v5.0

**SOLO PARA REDES PROPIAS O AUTORIZADAS — USO EDUCATIVO / LAB**

---

## Estructura del proyecto

```
wlab/
├── wlab.sh              ← Entry point (ejecutar esto)
├── README.md
└── lib/
    ├── constants.sh     ← Constantes globales (tiempos, rutas, etc.)
    ├── logging.sh       ← Funciones de log: info/ok/warn/die/dbg (todas a stderr)
    ├── state.sh         ← Variables de estado global mutables
    ├── cleanup.sh       ← Trap EXIT/INT: restaurar interfaz e iwd
    ├── args.sh          ← Parseo de argumentos (-i, -t, -c, -o)
    ├── meta.sh          ← Caché de metadatos por red (~/.wssids/)
    ├── preflight.sh     ← Verificaciones previas (root, dependencias)
    ├── iwd.sh           ← Detener/restaurar iwd antes/después de capturar
    ├── monitor.sh       ← Activar modo monitor (airmon-ng + fallback iw)
    ├── scan.sh          ← Escaneo de redes y resolución BSSID/canal desde SSID
    ├── clients.sh       ← Detección de clientes conectados al AP
    ├── deauth.sh        ← Ataque deauth: dirigido por cliente + broadcast
    ├── capture.sh       ← Captura del handshake y verificación
    └── output.sh        ← wpaclean, conversión (.22000/.hccapx) y resumen
```

---

## Uso

```bash
sudo ./wlab.sh -i wlan0 -t "NombreDeRed"
sudo ./wlab.sh -i wlan0 -t AA:BB:CC:DD:EE:FF -c 6
sudo ./wlab.sh -i wlan0 -t "MiRed" -o /tmp/capturas
```

### Opciones

| Flag | Descripción                          | Requerido |
|------|--------------------------------------|-----------|
| `-i` | Interfaz física (ej: `wlan0`)        | Sí        |
| `-t` | BSSID (`AA:BB:...`) o SSID (`"Red"`) | Sí        |
| `-c` | Canal (se autodetecta si se omite)   | No        |
| `-o` | Directorio de salida (default: `pwd`)| No        |

---

## Dependencias

### Obligatorias
```bash
sudo apt install aircrack-ng iwd
```

### Opcionales (mejoran la salida)
```bash
sudo apt install tshark              # Análisis EAPOL preciso
sudo apt install hcxtools            # Convierte a formato .22000 (hashcat moderno)
```

---

## Bugs corregidos vs v4.4

### Bug 1 — Falso positivo: "0 handshake" detectado como éxito
`aircrack-ng` imprime el string `"0 handshake"` cuando **no** hay handshake.
La v4.4 usaba `[[ -n "$frame_info" ]]` que era verdadero con ese string.

**Fix:** se extrae el número y se verifica `> 0`. Además se usa `tshark` como
método secundario verificando que haya al menos 2 frames EAPOL.

### Bug 2 — stdout contaminado en `detect_clients`
Las llamadas a `dbg()` dentro de una sustitución `$(...)` escribían a stdout,
corrompiendo el valor numérico e causando `syntax error: operand expected`.

**Fix:** `logging.sh` redirige **todas** las funciones de log a `stderr` con `>&2`.
Así `$(detect_clients)` solo captura el número limpio.

### Bug 3 — Deauth broadcast no funciona con clientes PMF/WPA2 modernos
El deauth broadcast (sin `-c cliente`) falla frecuentemente porque:
- Los APs modernos filtran frames broadcast de deauth no autorizados.
- Clientes con PMF (Protected Management Frames, 802.11w) ignoran deauths no cifrados.

**Fix:** `deauth.sh` implementa **deauth dirigido por MAC de cliente** usando `-c <mac>`
en `aireplay-ng`. Se envía un deauth específico a cada cliente detectado en el CSV,
más un broadcast como fallback. Esto fuerza la reautenticación individualmente.

### Bug 4 — Prompt interactivo de `airmon-ng` colgaba la ejecución
`airmon-ng check kill` preguntaba `[y/n]` interactivamente y bloqueaba ~40s.

**Fix:** se hace pipe de `echo "y"` a ambas llamadas de `airmon-ng`.

---

## Flujo de ejecución

```
parse_args → init_meta → load_meta
    → preflight (root + deps)
    → save_and_stop_iwd
    → start_monitor (airmon-ng + fallback iw)
    → resolve_target (caché o escaneo)
    → capture
        └── capture_once (× MAX_TRIES)
                ├── detect_clients
                ├── airodump-ng (background)
                ├── run_deauth (background)
                │     ├── deauth dirigido por cliente (× cada MAC)
                │     └── deauth broadcast
                └── _check_handshake (aircrack-ng + tshark)
    → optimize (wpaclean + cap2hccapx/hcxpcapngtool)
    → summary
    → cleanup (EXIT trap: airmon stop + restaurar iwd)
```
