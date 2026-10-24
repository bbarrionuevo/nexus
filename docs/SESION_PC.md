# Instrucciones para la sesión de Claude en el PC del dueño (Windows 11)

Esta sesión tiene acceso al PC. La sesión en la nube (desarrollo e investigación) no puede verla,
así que **el repositorio es el canal**: aquí recibís tareas y en la rama `pc-sesion` dejás los
resultados. Antes de actuar, leé `docs/REGLAS.md`: esas reglas mandan.

## Dónde está todo
- Despliegue: `%USERPROFILE%\nexus` (clon aparte que sigue `main`; no edites código ahí).
- Estado y logs: `%LOCALAPPDATA%\nexus` (`state\status.json`, `state\update.json`, `logs\*.log`).
- Claves: `%LOCALAPPDATA%\nexus\.env`. **Nunca muestres, copies ni subas su contenido.**
- Tareas programadas: `nexus-agente` (agente, se relanza solo) y `nexus-mantenimiento` (cada 30 min).

## Qué podés hacer sin pedir permiso
- Diagnosticar: estado de las tareas, logs, `status.json`, versión instalada (`git -C %USERPROFILE%\nexus log --oneline -1`).
- Reparar lo operativo: relanzar tareas (`Start-ScheduledTask`), reinstalar con
  `local\windows\install.ps1` si algo quedó roto, sincronizar la hora de Windows.
- Ejecutar comandos de **solo lectura** de nexus, por ejemplo `python -m nexus.check_keys` o
  `python -m nexus.transfers BMT,IOST,DCR` (desde `%USERPROFILE%\nexus\local` con `..\.venv\Scripts\python`).
- Publicar resultados en la rama `pc-sesion` (ver abajo).

## Qué NO podés hacer nunca
- Escribir la frase de aprobación de `update.py --aprobar` ni la de `risk --rearmar`. Esas
  confirmaciones son **del dueño, a mano**: es el control que impide que una IA cambie límites o
  el actualizador sin que él lo vea. No las automatices (ni con `echo` ni con tuberías).
- Cambiar `live`, límites de riesgo, permisos de claves o activar operaciones reales.
- Editar archivos del despliegue para "arreglar" algo: los cambios se hacen por PR a `main`.
- Mostrar o copiar secretos en el chat, en logs o en la rama `pc-sesion`.

## Cómo informar a la sesión en la nube
Escribí un archivo Markdown con fecha y resultados (sin secretos) y subilo a la rama `pc-sesion`.
Desde la carpeta del despliegue:
```powershell
$d = "$env:TEMP\nexus-pcsesion"; Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue
git clone -q --branch pc-sesion https://github.com/bbarrionuevo/nexus.git $d 2>$null
if (-not $?) { git clone -q https://github.com/bbarrionuevo/nexus.git $d; git -C $d checkout -q --orphan pc-sesion; git -C $d rm -rq . }
New-Item -ItemType Directory -Force "$d\reportes" | Out-Null
Set-Content -Encoding utf8 "$d\reportes\$(Get-Date -Format yyyyMMdd-HHmm).md" "<tu reporte aquí>"
git -C $d add reportes; git -C $d commit -qm "reporte del PC"; git -C $d push -q origin HEAD:pc-sesion
```

## Tareas pendientes (las actualiza la sesión en la nube)
1. Verificar que `nexus-agente` y `nexus-mantenimiento` estén en estado `Running`/`Ready` y que
   `state\status.json` tenga menos de 2 minutos. Si no, diagnosticar y reparar (relanzar o reinstalar).
2. Cuando el dueño haya fusionado el PR 18 y aprobado en el PC: correr
   `python -m nexus.transfers BMT,IOST,ATM,QUICK,DCR,TREE,PORTO,AGT,JCT` y subir el resultado a `pc-sesion`.
3. Medir la latencia del PC a MEXC y a Binance (10 pedidos a `/api/v3/time` de cada uno; mínimo,
   mediana y máximo en ms) y subirla a `pc-sesion`. Sirve para el criterio C6 (+200 ms).
