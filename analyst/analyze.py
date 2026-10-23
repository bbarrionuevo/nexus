"""Fase 2: envía los logs a Claude y escribe una propuesta de mejora en proposals/."""
import glob
import os
from pathlib import Path

import anthropic

logs = "".join(Path(p).read_text()[-20000:] for p in sorted(glob.glob("logs/*.log"))[-3:])
client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
msg = client.messages.create(
    model=os.environ.get("ANALYST_MODEL", "claude-sonnet-5-5"), max_tokens=4000,
    system="Eres analista cuantitativo de nexus. Nunca relajes los límites de compliance ni "
           "actives trading real. Propón cambios mínimos como un diff unificado.",
    messages=[{"role": "user", "content": f"Logs recientes:\n{logs or '(sin logs)'}"}])
Path("proposals").mkdir(exist_ok=True)
Path("proposals/latest.md").write_text(msg.content[0].text)
