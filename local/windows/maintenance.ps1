<# Cada 30 min: actualización segura (solo main con CI verde) y latido del PC a GitHub. #>
$Dir = (Resolve-Path "$PSScriptRoot\..\..").Path
$env:NEXUS_HOME = "$env:LOCALAPPDATA\nexus"
$Py = "$Dir\.venv\Scripts\python.exe"
& $Py "$Dir\local\windows\update.py" *>> "$env:NEXUS_HOME\logs\update.log"
& $Py "$Dir\local\windows\report_status.py" *>> "$env:NEXUS_HOME\logs\status.log"
