<# Ejecuta el agente en bucle: si termina (reinicio controlado del actualizador o un error),
   espera 10 s y lo vuelve a lanzar con la versión que esté activa en ese momento. #>
$Dir = (Resolve-Path "$PSScriptRoot\..\..").Path
$env:NEXUS_HOME = "$env:LOCALAPPDATA\nexus"
$Py = "$Dir\.venv\Scripts\python.exe"
$Log = "$env:NEXUS_HOME\logs\runner.log"
while ($true) {
  $env:NEXUS_VERSION = (git -C $Dir rev-parse --short HEAD)
  Add-Content $Log "$(Get-Date -Format s) arranca agente version $env:NEXUS_VERSION"
  Push-Location "$Dir\local"
  & $Py -m nexus.agent.maker_agent 2>> "$env:NEXUS_HOME\logs\agent_stderr.log"
  $Code = $LASTEXITCODE
  Pop-Location
  Add-Content $Log "$(Get-Date -Format s) agente terminó (código $Code); reinicio en 10 s"
  Start-Sleep -Seconds 10
}
