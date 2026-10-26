# Registra el ciclo desatendido de nexus en el Programador de tareas de Windows. Lo corre el duenio, una vez:
#
#   powershell -ExecutionPolicy Bypass -File tools\windows\registrar_ciclo.ps1
#   powershell -ExecutionPolicy Bypass -File tools\windows\registrar_ciclo.ps1 -Horas 03:17,15:17
#
# La tarea "nexus-ciclo" corre "pythonw -m nexus.secresearch.cycle" (sin ventana) desde <repo>\local con tu usuario, sin
# permisos de administrador y solo con tu sesion iniciada. Cada corrida termina sola (maximo 4 horas) y nunca
# se reprograma. Resultados en %LOCALAPPDATA%\nexus\secresearch\ (ciclo.md, para_claude.md, validate\).
# Quitarla: Unregister-ScheduledTask nexus-ciclo -Confirm:$false
# (Sin tildes a proposito: PowerShell 5 lee los .ps1 sin BOM como ANSI.)

param([string[]]$Horas = @("03:17"))
$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$py = Join-Path $repo ".venv\Scripts\pythonw.exe"
$local = Join-Path $repo "local"
$home_nexus = if ($env:NEXUS_HOME) { $env:NEXUS_HOME } else { Join-Path $env:LOCALAPPDATA "nexus" }
$catalogo = Join-Path $home_nexus "secresearch.yaml"

$faltan = @()
if (-not (Test-Path $py)) { $faltan += "el entorno de Python ($py)" }
if (-not (Get-Command forge -ErrorAction SilentlyContinue)) { $faltan += "forge en el PATH (Foundry)" }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { $faltan += "git en el PATH" }
if (-not (Test-Path $catalogo)) { $faltan += "el catalogo $catalogo" }
if ($faltan.Count -gt 0) {
    Write-Host "No se registro nada. Falta: $($faltan -join '; ')"
    exit 1
}

$accion = New-ScheduledTaskAction -Execute $py -Argument "-m nexus.secresearch.cycle" -WorkingDirectory $local
$cuando = @($Horas | ForEach-Object { New-ScheduledTaskTrigger -Daily -At $_ })
$opciones = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 4) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "nexus-ciclo" -Action $accion -Trigger $cuando -Settings $opciones -Force `
    -Description "nexus: cambios A-C, harness de propiedades y lineas base con Foundry. Local, FFI apagado, sin envios." | Out-Null

Write-Host "Listo: nexus-ciclo corre todos los dias a las $($Horas -join ', ')."
Write-Host "Probarlo ahora:    Start-ScheduledTask nexus-ciclo"
Write-Host "Ver si termino:    Get-ScheduledTaskInfo nexus-ciclo   (LastTaskResult 0 = sin fallas, 1 = con fallas para revisar)"
Write-Host "Resultados:        $home_nexus\secresearch\ciclo.md  y  para_claude.md  (progreso en ciclo.log)"
Write-Host "Quitarlo:          Unregister-ScheduledTask nexus-ciclo -Confirm:`$false"
