"""Billetera virtual para paper trading; registra cada decisión en JSONL."""
import json
import time
from decimal import Decimal as D
from pathlib import Path


class PaperWallet:
    def __init__(self, eur, path="state/paper.json", journal="logs/paper_trades.jsonl"):
        self.path, self.journal = Path(path), Path(journal)
        self.eur = D(str(eur))
        if self.path.exists():
            self.eur = D(json.loads(self.path.read_text())["eur"])

    def execute(self, opp, meta=None):
        self.eur = opp.eur_out - opp.eur_in + self.eur
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps({"eur": str(self.eur)}))
        self.log("executed", opp, meta)

    def log(self, action, opp, meta=None):
        self.journal.parent.mkdir(parents=True, exist_ok=True)
        rec = {"ts": time.time(), "action": action, "roi_pct": str(opp.net_roi_pct),
               "profit": str(opp.net_profit), "reason": opp.reason, "wallet_eur": str(self.eur),
               "meta": meta or {}}
        with self.journal.open("a") as f:
            f.write(json.dumps(rec) + "\n")
