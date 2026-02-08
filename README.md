# 🧹 mac_cleanup.sh

Script de limpieza segura para macOS. Borra caches, logs, papelera y audita LaunchAgents — todo desde la terminal.

## Requisitos

- macOS
- Terminal con **Full Disk Access** (Warp, iTerm2, Terminal.app, etc.)

### Configurar Full Disk Access

Sin esto, el script no podrá borrar la papelera ni algunos logs protegidos.

1. Abre **Ajustes del Sistema → Privacidad y Seguridad → Full Disk Access**
2. Haz clic en el candado 🔒 para desbloquear
3. Agrega tu terminal (Warp, iTerm2, Terminal.app)
4. Reinicia la terminal

## Instalación

```bash
git clone https://github.com/tu-usuario/mac-cleanup.git
cd mac-cleanup
chmod +x mac_cleanup.sh
```

## Uso

```bash
# Ver qué haría sin ejecutar nada (recomendado la primera vez)
./mac_cleanup.sh --dry-run

# Ejecutar limpieza (solo caches de apps conocidas)
./mac_cleanup.sh --run --smart-caches

# Limpieza + flush DNS
./mac_cleanup.sh --run --smart-caches --flush-dns

# Limpieza + deshabilitar LaunchAgents de terceros
./mac_cleanup.sh --run --smart-caches --disable-launchers
```

## Opciones

| Flag | Descripción |
|------|-------------|
| `--dry-run` | Simula la limpieza sin borrar nada (default) |
| `--run` | Ejecuta la limpieza |
| `--smart-caches` | Solo borra caches de apps conocidas (Adobe, Chrome, Slack, VS Code, etc.) |
| `--flush-dns` | Limpia la cache DNS al finalizar |
| `--disable-launchers` | Mueve LaunchAgents de terceros a `~/LaunchAgents.disabled` |
| `--help` | Muestra la ayuda |

## Qué limpia

- **Saved Application State** — estados guardados de apps
- **User Caches** — caches de aplicaciones (todo o solo apps conocidas con `--smart-caches`)
- **User Logs** — archivos `.log` en `~/Library/Logs`
- **Papelera** — contenido de `~/.Trash`

## Qué audita (sin modificar)

- `~/Library/LaunchAgents` — agentes de usuario
- `/Library/LaunchAgents` — agentes del sistema
- `/Library/LaunchDaemons` — daemons del sistema

## Logs

Cada ejecución genera un log en el Desktop: `~/Desktop/mac_cleanup_YYYY-MM-DD_HH-MM-SS.log`

Se mantienen los últimos 5 logs automáticamente.

## Tips

- Cierra Chrome, Safari, Slack y Spotify antes de ejecutar con `--run`
- Usa `--dry-run` primero para revisar qué se va a borrar
- Reinicia tu Mac después de la limpieza para asegurar estabilidad
- Si usas `--disable-launchers`, los plists se mueven a `~/LaunchAgents.disabled` (puedes restaurarlos manualmente)

## Licencia

MIT
