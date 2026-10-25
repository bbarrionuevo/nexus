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
  `nexus-agente` (al iniciar sesión, se reinicia sola) y `nexus-mantenimiento` (cada 10 min). El
  mantenimiento agrega la tercera, `nexus-dashboard` (el tablero local, ver abajo).
- Desactiva la suspensión con corriente (`-KeepSleep` para no tocarla).
- **Autorreparación:** si el agente se detiene, Windows lo relanza en menos de 1 minuto, y el
  mantenimiento (cada 10 min) también lo verifica.
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
| Abrir el tablero | `start http://localhost:8765` (o el acceso directo "nexus tablero" del escritorio) |
| Detener el tablero | `Stop-ScheduledTask nexus-dashboard` (el mantenimiento lo vuelve a lanzar) |
| Desinstalar | `Unregister-ScheduledTask nexus-agente,nexus-mantenimiento,nexus-dashboard -Confirm:$false` |

## Tablero en tiempo real
Abrí **http://localhost:8765** en el navegador (o el acceso directo **nexus tablero** del escritorio).
Se actualiza solo: el estado del agente cada 5 segundos y las oportunidades cada minuto.

- **Qué muestra:** si el agente está en marcha, el modo paper y el interruptor KILL, la ganancia de
  la estrategia vigente frente al grupo de control (con la curva acumulada), los criterios para pasar
  a dinero real, el resultado por clima de mercado, los pares del laboratorio (y cuáles están en
  pausa), las últimas vueltas, los avisos del agente, el riesgo del día y de la semana, y las
  oportunidades del radar (rulo, P2P, diferencias de funding, paper de funding y carry, rendimiento
  seguro).
- **Seguridad:** es de **solo lectura**: no tiene botones ni puede enviar órdenes. Solo responde en
  esta PC (127.0.0.1): no se puede abrir desde otra máquina. No lee el `.env`.
- **Cómo corre:** la tarea `nexus-dashboard` lo lanza al iniciar sesión y lo relanza sola si se cae.
  El mantenimiento crea esa tarea si no existe, así que llega sola a una PC ya instalada (en menos
  de 30 minutos después de actualizarse). Cuando se instala una versión nueva, el tablero se
  reinicia solo con el código nuevo. Su log está en `logs\dashboard.log`.

## Dinero real
El repositorio nunca activa el modo real: lo activás **vos en la PC** con una autorización que vence
(máximo 100 € y 7 días). Hasta entonces el agente opera solo en paper.

1. **Subcuenta en MEXC (recomendado, R-01).** Creá una subcuenta "nexus" y pasale solo el capital que
   querés que opere. Así, pase lo que pase, el agente no puede tocar más que eso. Con `--todo` opera
   siempre **todo** lo que haya en la subcuenta (hasta 100 €): para invertir más, transferí más ahí.
2. **Clave de API en esa subcuenta:**
   - Permisos: **Spot: ver y operar**. **Sin retiro**, sin futuros y sin margen.
   - Vinculada a la IP pública de la PC (`irm https://ifconfig.me`). Si tu IP cambia, la clave deja de
     funcionar: el agente no puede operar ese par, se bloquea y te avisa (actualizás la IP en MEXC).
3. **Pegala en el `.env`** reemplazando la de solo lectura (`MEXC_API_KEY` y `MEXC_SECRET_KEY`) y
   verificá, sin que se muestren las claves:
   ```powershell
   cd $env:USERPROFILE\nexus\local; ..\.venv\Scripts\python -m nexus.check_keys
   ```
4. **Autorizá** (pide confirmar que la clave no tiene retiro y escribir una frase exacta):
   ```powershell
   ..\.venv\Scripts\python -m nexus.agent.authorize --todo --dias 7 --pares XXXUSDT --calibracion
   ```
   `--todo` = siempre todo el capital de la subcuenta (USDT + lo invertido en la posición), hasta
   100 €. El monto por vuelta se recalcula cada 10 minutos con el saldo real, solo entre vueltas: las
   ganancias se reinvierten solas. `--capital N` en vez de `--todo` fija un monto menor. Nunca supera
   el máximo por posición de la config de riesgo (40 €); con más capital, el modo automático lo
   reparte entre varios pares.
   **No hace falta reiniciar**: el agente toma la autorización solo en menos de un minuto. Si alguna
   vez querés reiniciarlo, usá el reinicio controlado (guarda el estado y cancela sus órdenes):
   `New-Item $env:LOCALAPPDATA\nexus\state\RESTART`. Hay un solo agente por PC: si quedara uno
   huérfano, el bucle lo detiene al arrancar y un lock impide que dos operen a la vez.
   `XXXUSDT` es el par que elijamos con la evidencia del laboratorio (te lo indico en el informe).
   `--calibracion` permite empezar antes de cumplir los criterios de paper (excepción de REGLAS.md).
   Sin esa opción, solo autoriza si la evidencia cumple todo R-15.

   **Modo automático** (en vez de elegir el par a mano):
   ```powershell
   ..\.venv\Scripts\python -m nexus.agent.authorize --todo --dias 7 --auto 1 --calibracion
   ```
   El agente opera los mejores pares **promovidos** por el laboratorio (`--auto 1` a `--auto 3`; el
   capital se reparte entre los que estén promovidos en ese momento). Cuando el laboratorio promueve
   uno mejor, cambia de par **solo si no tiene posición ni órdenes abiertas**: nunca abandona una
   posición. Si no hay ninguno promovido, sigue en paper hasta que lo haya. Mismos topes (100 €, 7 días)
   y mismos límites de pérdida.
5. **Seguimiento:** el tablero muestra la tarjeta "Dinero real". El detalle está en
   `state\real_trades.jsonl` (vueltas reales) y `state\orders.jsonl` (cada orden, con hash
   encadenado). El mismo par sigue también en paper, para comparar lo simulado contra lo real.

| Acción | Comando |
|---|---|
| Dejar de abrir posiciones reales | `..\.venv\Scripts\python -m nexus.agent.authorize --revocar` |
| Cancelar todas las órdenes en MEXC | `Set-Content $env:LOCALAPPDATA\nexus\KILL 2` |
| Cancelar todo y vender a mercado | `Set-Content $env:LOCALAPPDATA\nexus\KILL 3` |
| Ver la autorización vigente | `..\.venv\Scripts\python -m nexus.agent.authorize --estado` |
| Desbloquear un par tras revisarlo en MEXC | `..\.venv\Scripts\python -m nexus.agent.authorize --desbloquear XXXUSDT` |
| Rearmar tras un halt del dinero real | `..\.venv\Scripts\python -m nexus.agent.risk --rearmar --real` |

**Si un par queda BLOQUEADO** (saldo distinto de lo esperado, orden ajena o rechazos seguidos):
1. El agente no vuelve a operar ese par por su cuenta.
2. Revisá en MEXC las órdenes y el saldo de esa moneda. Si no querés que quede nada, vendelo a mano.
3. Corré `--desbloquear`: lo que haya de esa moneda queda como residuo no gestionado y el par arranca de cero.

Los límites de riesgo del dinero real se llevan aparte del paper (`state\risk_real.json`): 2 € por
día, 4 € por semana y 8 € en total (halt que solo levantás vos).

## Comunicación con la sesión de Claude
- **Latido cada 5 minutos** (tarea `nexus-latido`, la crea el mantenimiento). Publica en la rama
  `pc-status`: estado del agente, dinero real (autorización, órdenes y vueltas recientes, riesgo
  real), chequeo previo y resultado de los comandos remotos. Nunca incluye claves.
- **Chequeo previo** cada 30 minutos: clave, permiso de trading, saldo USDT, reloj, latencia y reglas
  de cada par. A mano: `..\.venv\Scripts\python -m nexus.preflight XXXUSDT`.
- **Comandos de seguridad** (issues abiertos con la etiqueta `pc-comando`, creados con tu cuenta):
  la sesión de Claude puede pedir **pausar** (no abrir posiciones), **cancelar** (cancelar órdenes
  reales), **reanudar** (solo lo que pausó ella) y
  **diagnóstico**. No puede autorizar, desbloquear, rearmar, vender a mercado ni cambiar límites.
  Un KILL tuyo nunca lo quita. Para apagar el canal: `New-Item $env:LOCALAPPDATA\nexus\state\remote_off`.

### Cuándo la sesión de Claude pausa (reglas fijadas de antemano)
Solo **pausa** (no abre posiciones nuevas) o **cancela órdenes**. Nunca vende, nunca reanuda algo que
vos pausaste y siempre te avisa del motivo. Lo hace si en el latido ve cualquiera de estas cosas:
- Un par real **bloqueado** o en **estado desconocido** por más de 10 minutos.
- Rechazos del exchange que se repiten (clave, IP, reloj o saldo) o el chequeo previo falla.
- La calibración muestra que el real **pierde** mientras el gemelo en paper gana en el mismo período,
  con al menos 10 vueltas reales: el modelo de paper no representa la realidad de ese par.
- El latido muestra errores de datos sostenidos o el agente sin actualizar su estado.
Reanuda (solo lo que pausó) cuando la causa desapareció, y te lo informa.

## Cómo se actualiza solo
Cada 10 min `update.py` compara con `origin/main`. Activa la versión nueva **solo** si se cumplen
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
