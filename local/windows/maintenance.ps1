<# Cada 30 min: actualización segura (solo main con CI verde), autorreparación del agente y latido. #>
$Dir = (Resolve-Path "$PSScriptRoot\..\..").Path
$env:NEXUS_HOME = "$env:LOCALAPPDATA\nexus"
$env:PYTHONUTF8 = "1"
$Py = "$Dir\.venv\Scripts\python.exe"
& $Py "$Dir\local\windows\update.py" *>> "$env:NEXUS_HOME\logs\update.log"
try {
  $t = Get-ScheduledTask -TaskName "nexus-agente" -ErrorAction Stop
  if ($t.State -ne "Running") {
    Add-Content "$env:NEXUS_HOME\logs\runner.log" "$(Get-Date -Format s) mantenimiento: la tarea estaba '$($t.State)'; se relanza"
    Start-ScheduledTask -TaskName "nexus-agente"
  }
} catch {
  Add-Content "$env:NEXUS_HOME\logs\runner.log" "$(Get-Date -Format s) mantenimiento: no se pudo verificar la tarea: $_"
}
& $Py "$Dir\local\windows\report_status.py" *>> "$env:NEXUS_HOME\logs\status.log"
