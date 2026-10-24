# Operación en Windows 11

## Instalación (una sola vez)
En PowerShell, **sin** permisos de administrador:
```powershell
irm https://raw.githubusercontent.com/bbarrionuevo/nexus/main/local/windows/install.ps1 -OutFile $env:TEMP\nexus-install.ps1
powershell -ExecutionPolicy Bypass -File $env:TEMP\nexus-install.ps1
```
- Instala Git y Python 3.12 si faltan (winget) y clona `main` en `%USERPROFILE%\nexus`. Es un clon
  aparte del de desarrollo y solo sigue versiones validadas.
- Corre los tests; si fallan, no instala.
- Crea `%LOCALAPPDATA%\nexus` (estado, logs y `.env` privado) y dos tareas programadas:
  `nexus-agente` (al iniciar sesión, se reinicia sola) y `nexus-mantenimiento` (cada 30 min).
- Desactiva la suspensión con corriente (`-KeepSleep` para no tocarla).
- **Autorreparación:** si el agente se detiene, Windows lo relanza en menos de 1 minuto, y el
  mantenimiento (cada 30 min) también lo verifica.
- **Reinstalar o actualizar el instalador:** volver a correr los dos comandos de arriba. Detiene el
  agente anterior, instala la última versión validada de `main` y vuelve a registrar las tareas.
- **Reinicios de Windows:** el agente arranca al iniciar sesión. Si Windows Update reinicia la PC,
  vuelve a operar cuando inicies sesión. El vigilante te avisa por mail si el PC deja de reportar.

## Claves de MEXC (solo en el PC)
```powershell
notepad $env:LOCALAPPDATA\nexus\.env            # completar MEXC_API_KEY y MEXC_SECRET_KEY
cd $env:USERPROFILE\nexus\local; ..\.venv\Scripts\python -m nexus.check_keys
```
`check_keys` muestra los permisos, los saldos y la comisión real **sin mostrar las claves**.

## Día a día
| Acción | Comando |
|---|---|
| Ver estado | `Get-Content $env:LOCALAPPDATA\nexus\state\status.json` |
| Ver log | `Get-Content $env:LOCALAPPDATA\nexus\logs\agent.log -Tail 50` |
| **Parar entradas (emergencia)** | `New-Item $env:LOCALAPPDATA\nexus\KILL` |
| Reanudar | `Remove-Item $env:LOCALAPPDATA\nexus\KILL` |
| Detener el agente | `Stop-ScheduledTask nexus-agente` |
| Aprobar una versión con cambios protegidos | `..\.venv\Scripts\python ..\local\windows\update.py --aprobar` (desde `%USERPROFILE%\nexus\local`) |
| Rearmar tras un halt permanente | `..\.venv\Scripts\python -m nexus.agent.risk --rearmar` |
| Desinstalar | `Unregister-ScheduledTask nexus-agente,nexus-mantenimiento -Confirm:$false` |

## Cómo se actualiza solo
Cada 30 min `update.py` compara con `origin/main`. Activa la versión nueva **solo** si se cumplen
todas estas condiciones:
- El CI está en verde.
- No hay cambios protegidos sin tu aprobación local. Tu aprobación de una versión sigue valiendo
  para las versiones posteriores que **no** vuelvan a tocar rutas protegidas (así no tenés que
  re-aprobar si main avanza con mejoras comunes antes de que el PC instale lo aprobado).
- No hay posiciones abiertas.
- Los tests pasan en el PC.

Después pide un reinicio controlado, verifica que el agente responda con la versión nueva y, si no,
vuelve a la anterior. Todo queda en `state\update.json` y `logs\update.log`.

## Avisos por mail
El vigilante (cada hora) y el informe diario se publican como issues de GitHub asignados a vos, y
GitHub te los manda por mail. Revisá en GitHub → Settings → Notifications que el mail sea el que
querés y que las notificaciones por email estén activadas.

El latido del PC se publica en la rama `pc-status`. Para eso, el clon del PC necesita poder hacer
`git push` (por ejemplo, con Git Credential Manager tras `git push` manual una vez).
