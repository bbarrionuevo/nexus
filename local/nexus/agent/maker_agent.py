"""Agente autónomo de market making — SOLO PAPER (no existe código que envíe órdenes).

- Datos públicos de MEXC (REST). Si hay claves en NEXUS_HOME/.env, verifica la comisión real al
  arrancar y usa la mayor entre la configurada y la real (nunca una menor).
- Toda entrada pasa por el veto del RiskManager (R-03); las salidas siempre se permiten.
- Datos viejos => se cancela la compra pendiente (R-07).
- Estado del paper, riesgo y latido en NEXUS_HOME/state (R-09); logs rotados en NEXUS_HOME/logs.
- Diario de cada vuelta cerrada (state/trades.jsonl) y evaluación de los criterios R-15.
- Laboratorio: además de los pares operados, mide en paper 10-12 pares de MEXC elegidos solos por
  spread y volumen (se renuevan cada pocas horas). No pasan por el riesgo ni afectan al capital:
  solo generan evidencia para decidir qué pares operar. Un par cuyas últimas N vueltas pierden en
  promedio se pausa (no vuelve a elegirse) por unas horas.
- Los pedidos de cada ciclo van en paralelo: desde el PC cada uno tarda ~270 ms y en serie las
  órdenes simuladas quedaban viejas (más llenados adversos y stops tardíos que un bot real).
python -m nexus.agent.maker_agent
"""
import json
import logging
import os
import sys
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from logging.handlers import RotatingFileHandler
from pathlib import Path

import yaml

from .. import allocator, evidence, paths
from ..exchanges.mexc import MexcReadOnly, parse_fee
from ..live_paper_maker import Book
from .risk import RiskManager

CFG = Path(__file__).resolve().parents[2] / "config" / "agent.yaml"
log = logging.getLogger("nexus.agent")
POOL = ThreadPoolExecutor(max_workers=8, thread_name_prefix="datos")


def fetch_many(client, syms, timeout=15):
    """Libro y operaciones de varios pares EN PARALELO: {par: (libro, operaciones) | Exception}."""
    futs = {s: (POOL.submit(client.book_ticker, s), POOL.submit(client.trades, s)) for s in syms}
    out = {}
    for s, (fb, ft) in futs.items():
        try:
            out[s] = (fb.result(timeout=timeout), ft.result(timeout=timeout))
        except Exception as e:                                        # noqa: BLE001 (se informa)
            out[s] = e
    return out


def draining(max_age_s=2400):
    """True si el actualizador pospuso hace poco una versión validada SOLO por posiciones abiertas.

    Entonces no se abren posiciones nuevas: las abiertas cierran (como maker, stop o tiempo máximo)
    y en el siguiente ciclo la actualización entra. Si pospuso por otra causa (CI, aprobación), no.
    """
    u = paths.read_json(paths.state("update.json"), {})
    reasons = u.get("reasons") or []
    return (u.get("result") == "pospuesta" and time.time() - u.get("ts", 0) < max_age_s
            and len(reasons) == 1 and reasons[0].startswith("hay posiciones abiertas"))


class Gate:
    """Adaptador entre los libros (estrategia) y el RiskManager (veto)."""

    def __init__(self, risk):
        self.risk, self.books = risk, {}

    def allow_entry(self, notional, exposure):
        if draining():
            self.risk.last_reason = "vaciando posiciones para instalar una actualización"
            return False
        return self.risk.allow_entry(notional, exposure)

    def exposure(self):
        return sum(b.exposure() for b in self.books.values())

    def record_order(self):
        self.risk.record_order()

    def on_close(self, pnl, was_stop):
        self.risk.on_close(pnl, was_stop)
        log.info(json.dumps({"event": "close", "pnl": round(pnl, 4), "stop": was_stop,
                             "day_pnl": round(self.risk.s["pnl_day"], 4)}))


def setup_logging():
    h = RotatingFileHandler(paths.logs("agent.log"), maxBytes=5_000_000, backupCount=5, encoding="utf-8")
    h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    handlers = [h] + ([logging.StreamHandler()] if sys.stderr and sys.stderr.isatty() else [])
    logging.basicConfig(level=logging.INFO, handlers=handlers)


def load_config():
    cfg = yaml.safe_load(CFG.read_text(encoding="utf-8"))
    if cfg.get("live") is not False:
        raise SystemExit("live debe ser false: el modo real no existe en esta versión (R-02).")
    return cfg


def verified_fees(client, cfg):
    maker, taker = cfg["maker_fee_pct"], cfg["taker_fee_pct"]
    if not client.has_keys:
        log.warning("sin claves MEXC: comisiones no verificadas, se usan las configuradas")
        return maker, taker
    for sym in cfg["symbols"]:
        try:
            f = parse_fee(client.trade_fee(sym))
        except Exception as e:
            log.warning("no se pudo verificar comisión de %s: %s", sym, type(e).__name__)
            continue
        if f:
            maker, taker = max(maker, f[0]), max(taker, f[1])
    log.info("comisiones en uso maker=%.4f%% taker=%.4f%%", maker, taker)
    return maker, taker


def feed(bk, trades, seen):
    """Pasa al libro solo las operaciones NUEVAS de MEXC (defecto 3).

    Se llama ANTES de on_book: las operaciones ocurridas desde el sondeo anterior se evalúan contra la
    orden que estaba puesta en ese intervalo, y recién después se mueve la orden al libro nuevo. Al
    revés, el paper esquivaba compras perdedoras y stops (sesgo optimista).
    En el primer sondeo de un libro (arranque, reinicio o par nuevo del laboratorio) las operaciones son
    anteriores a cualquier orden nuestra: solo se marcan como vistas.
    """
    apply_trades(bk, fresh_trades(trades, seen))


def live_auth():
    from .live import authorization
    return authorization()


def books_snapshot(gate, desk):
    """Libros para paper_books.json: el actualizador lee de acá si hay posiciones abiertas (R-13),
    así que los reales van también (clave PAR#real) aunque su estado completo esté en live_books.json."""
    return {x: b.to_dict() for x, b in gate.books.items()} | (
        {f"{x}#real": b.to_dict() for x, b in desk.books.items()} if desk else {})


def live_wanted():
    """Hay autorización vigente o quedó una posición/orden real guardada que hay que gestionar."""
    from .live import STATE_FILE
    saved = paths.read_json(paths.state(STATE_FILE), {})
    return bool(live_auth()) or any(isinstance(d, dict) and (d.get("state") == "long" or d.get("order"))
                                    for d in saved.values())


STRATEGY = {"tag": None}                                       # versión de la estrategia (agent.yaml)
CONTROL_TAG = "control"                                        # misma estrategia SIN filtro de volatilidad


class Market:
    """Clima general medido con BTC/USDT en tiempo real: volatilidad y variación de los últimos 15 min.
    Pocas medidas y simples a propósito: describir el mercado, no predecirlo."""

    def __init__(self, now=time.time):
        self.now, self.mids = now, deque(maxlen=900)

    def update(self, bt):
        b, a = float(bt["bidPrice"]), float(bt["askPrice"])
        if b > 0 and a > 0:
            self.mids.append((self.now(), (a + b) / 2))

    def snapshot(self):
        if len(self.mids) < 10:
            return {}
        t1, p1 = self.mids[-1]
        old = [(t, m) for t, m in self.mids if t >= t1 - 900]
        pts = list(self.mids)[-60:]
        import math
        var = sum(math.log(b / a) ** 2 for (_, a), (_, b) in zip(pts, pts[1:]))
        secs = pts[-1][0] - pts[0][0]
        return {"btc_ret15_pct": round((p1 / old[0][1] - 1) * 100, 3) if old else None,
                "btc_vol_1m_pct": round(math.sqrt(var / secs * 60) * 100, 4) if secs > 0 else None}


MARKET = Market()


def fresh_trades(trades, seen):
    """Operaciones que no se habían visto todavía (y las marca como vistas)."""
    out = []
    for t in sorted(trades, key=lambda t: t["time"]):
        k = (t["time"], t["price"], t["qty"], t["isBuyerMaker"])
        if k not in seen:
            seen.add(k)
            out.append(t)
    return out


def apply_trades(bk, new):
    """Aplica operaciones nuevas a un libro; su primer lote solo lo prepara (defecto 3)."""
    if not getattr(bk, "primed", False):
        bk.primed = True
        return
    for t in new:
        bk.on_trade(float(t["price"]), float(t["qty"]), t["isBuyerMaker"])


def journal(entry, strategy=None):
    """Agrega una vuelta cerrada al diario (una línea JSON). Tolerante a bloqueos breves.
    `model` marca la versión del modelo de llenado y `strategy` la de la estrategia: cada versión
    tiene que probarse por sí misma (la evidencia de una no cuenta para otra)."""
    line = json.dumps(entry | {"model": evidence.FILL_MODEL, "strategy": strategy or STRATEGY["tag"]}) + "\n"
    for _ in range(5):
        try:
            with open(paths.state("trades.jsonl"), "a", encoding="utf-8") as f:
                f.write(line)
            return
        except OSError:
            time.sleep(0.2)
    log.warning("no se pudo escribir el diario de vueltas")


STABLE = ("USDC", "USDT", "FDUSD", "TUSD", "DAI", "USDE", "PYUSD", "USD1", "EUR", "EURC", "EURQ", "USDQ")


def select_lab(client, lab_cfg, exclude):
    """Elige pares USDT de MEXC con volumen suficiente y spread en rango (datos públicos)."""
    vol = {t["symbol"]: float(t.get("quoteVolume") or 0) for t in client._get("/api/v3/ticker/24hr")}
    out = []
    for t in client._get("/api/v3/ticker/bookTicker"):
        sym = t["symbol"]
        if not sym.endswith("USDT") or sym in exclude:
            continue
        base = sym[:-4]
        if base in STABLE or base.endswith(("3L", "3S", "5L", "5S", "UP", "DOWN")):
            continue
        b, a = float(t.get("bidPrice") or 0), float(t.get("askPrice") or 0)
        if b <= 0 or a <= 0:
            continue
        spread = (a / b - 1) * 100
        if lab_cfg["min_spread_pct"] <= spread <= lab_cfg["max_spread_pct"] \
                and vol.get(sym, 0) >= lab_cfg["min_quote_volume_usdt"]:
            out.append((vol[sym], sym, round(spread, 3)))
    out.sort(reverse=True)
    return [(s, sp) for _, s, sp in out[:lab_cfg["max_symbols"]]]


def save_state(name, data, tries=5):
    """Escritura tolerante: en Windows un antivirus o un lector puede trabar el archivo un instante."""
    for i in range(tries):
        try:
            paths.write_json_atomic(paths.state(name), data)
            return True
        except OSError as e:
            if i == tries - 1:
                log.warning("no se pudo guardar %s: %s", name, e)
            time.sleep(0.2)
    return False


def build_desk(cfg, client, maker, taker):
    """Libros con DINERO REAL (Fase 6), solo si hay autorización local vigente del dueño o quedó una
    posición/orden real de antes (hay que seguir gestionándola aunque la autorización venza)."""
    from . import live
    auth = live.authorization()
    saved = paths.read_json(paths.state(live.STATE_FILE), {})
    pending = [s for s, d in saved.items() if isinstance(d, dict)
               and (d.get("state") == "long" or d.get("order") or d.get("unknown"))]
    syms = sorted(set((auth or {}).get("symbols", [])) | set(pending))
    if not syms:
        return None
    from ..exchanges.mexc_trade import MexcTrader
    trader = MexcTrader()
    try:
        if not trader.has_keys:
            raise RuntimeError("no hay clave de MEXC en .env")
        acc = trader.account()
        if acc.get("canTrade") is False:
            raise RuntimeError("la clave de MEXC no tiene permiso de trading")
        if acc.get("canWithdraw") and not (auth or {}).get("sin_retiro_confirmado"):
            raise RuntimeError("R-01: la cuenta informa retiros y el dueño no confirmó que la clave no los tenga")
    except Exception as e:                                           # noqa: BLE001
        log.error("MODO REAL NO ACTIVADO: %s", e)
        return None
    lmaker, ltaker = verified_fees(client, {**cfg, "symbols": syms})
    rgate = Gate(RiskManager(cfg["risk"], state_path=paths.state("risk_real.json")))
    olog, books = live.OrderLog(), {}
    notional = min(float((auth or {}).get("capital_eur") or live.CALIBRATION_MAX_EUR), cfg["risk"]["max_position_eur"])
    for s in syms:
        try:
            rules = live.Rules(trader.exchange_info(s), s)
        except Exception as e:                                       # noqa: BLE001
            log.error("real %s: sin reglas del par (%s): no se opera", s, e)
            continue
        bk = live.LiveBook(s, trader, rules, olog, save=lambda: None, notional=notional, maker=lmaker, taker=ltaker,
                           stop_pct=cfg["stop_pct"], min_edge_pct=cfg["min_edge_pct"],
                           max_hold_s=cfg["max_hold_min"] * 60, gate=rgate, on_closed=live.journal_real,
                           max_vol_1m_pct=cfg.get("max_vol_1m_pct"), context=MARKET.snapshot)
        if s in saved:
            bk.load(saved[s])
        bk.entry_allowed = lambda s=s: s in ((live.authorization() or {}).get("symbols") or [])
        books[s] = rgate.books[s] = bk
    if not books:
        return None
    desk = live.Desk(trader, client, rgate, books, olog)
    for bk in books.values():
        bk.save_cb = desk.save
        try:
            px = float(client.book_ticker(bk.sym)["bidPrice"])
        except Exception:                                            # noqa: BLE001
            px = bk.entry or 0.0
        bk.reconcile(acc.get("balances", []), px)
    log.warning("MODO REAL activo en %s (autorización: %s)", list(books), auth)
    return desk


def main():
    paths.load_env()
    setup_logging()
    cfg = load_config()
    STRATEGY["tag"] = cfg.get("strategy_tag")
    client = MexcReadOnly()
    maker, taker = verified_fees(client, cfg)
    risk = RiskManager(cfg["risk"])
    gate = Gate(risk)
    saved = paths.read_json(paths.state("paper_books.json"), {})
    for x in cfg["symbols"]:
        bk = Book(x, notional=cfg["risk"]["max_position_eur"], maker=maker, taker=taker, stop_pct=cfg["stop_pct"],
                  min_edge_pct=cfg["min_edge_pct"], max_hold_s=cfg["max_hold_min"] * 60, gate=gate,
                  on_closed=lambda e: journal(e | {"lab": False}), max_vol_1m_pct=cfg.get("max_vol_1m_pct"),
                  context=MARKET.snapshot)
        if x in saved:
            bk.load(saved[x])
        gate.books[x] = bk
    lab = Lab(client, cfg, maker, taker)
    desk = build_desk(cfg, client, maker, taker)
    version = os.environ.get("NEXUS_VERSION", "desconocida")
    log.info("arranque version=%s simbolos=%s home=%s", version, cfg["symbols"], paths.home())
    seen = {x: set() for x in gate.books}
    last_ok = {x: 0.0 for x in gate.books}
    errors, last_status = [], 0.0
    log.info("comisiones maker=%s taker=%s; estado cargado: %s", maker, taker,
             {x: b.state for x, b in gate.books.items()})
    last_eval, ev, last_bal, last_desk = 0.0, {}, time.time(), time.time()
    while True:
        if desk is None and time.time() - last_desk >= 60 and live_wanted():
            last_desk = time.time()                  # p. ej. MEXC no respondía al arrancar con una posición real
            desk = build_desk(cfg, client, maker, taker)
        try:
            if step(gate, client, cfg, seen, last_ok, errors) == "restart":
                lab.save()
                if desk:
                    desk.shutdown()
                    save_state("paper_books.json", books_snapshot(gate, desk))
                return
            if desk:
                desk.step(cfg["stale_data_s"])
                if time.time() - last_bal >= 600:
                    last_bal = time.time()
                    desk.check_balances()
            lab.step()
        except Exception:
            log.exception("error inesperado en el ciclo (el agente sigue)")
            errors.append(time.time())
            time.sleep(5)
        if time.time() - last_status >= 30:
            last_status = time.time()
            errors[:] = [e for e in errors if time.time() - e < 3600]
            save_state("paper_books.json", books_snapshot(gate, desk))
            lab.save()
            if desk:
                desk.save()
            if time.time() - last_eval >= 300:
                last_eval = time.time()
                try:
                    ev = evidence.evaluate(paths.state("trades.jsonl"), strategy=STRATEGY["tag"])
                    ev.pop("daily", None)
                except Exception:
                    log.exception("no se pudo evaluar la evidencia")
            save_state("status.json", {
                "ts": time.time(), "version": version, "mode": "real+paper" if desk else "paper", "fees": [maker, taker],
                "books": [b.mark() for b in gate.books.values()], "risk": risk.snapshot(),
                "risk_block": risk.last_reason, "errors_last_hour": len(errors),
                "data_age_s": {x: round(time.time() - t, 1) for x, t in last_ok.items()},
                "lab": lab.status(), "evidence": ev, "market": MARKET.snapshot(),
                "live": desk.status(live_auth()) if desk else None})
        time.sleep(cfg["poll_seconds"])


class Lab:
    """Pares de laboratorio: paper puro (sin riesgo ni capital), sondeados de a pocos por ciclo."""

    def __init__(self, client, cfg, maker, taker):
        self.client, self.cfg, self.maker, self.taker = client, cfg.get("lab") or {}, maker, taker
        self.main = set(cfg["symbols"])
        self.base = cfg
        self.books, self.seen, self.order, self.i, self.selected_at = {}, {}, [], 0, 0.0
        self.saved = paths.read_json(paths.state("lab_books.json"), {})
        self.recent = {}                                      # últimas vueltas por par (pausa)
        self.recent_kinds = {}                                # tipos de cierre recientes (pausa rápida)
        self.control = {}                                     # mismo par, misma estrategia SIN filtro de volatilidad
        self.paused = {s: t for s, t in paths.read_json(paths.state("lab_paused.json"), {}).items()
                       if t > time.time()}
        self.alloc = paths.read_json(paths.state("allocator.json"), {})   # promociones (explorar/explotar)

    def is_paused(self, sym):
        return self.paused.get(sym, 0) > time.time()

    def on_closed(self, e, variant=None):
        """Registra la vuelta y pausa el par si sus últimas N vueltas pierden en promedio, o antes si
        acumula muchos stops seguidos de cerca (CHOMP perdió 12,7 € en 15 vueltas antes de pausarse).
        variant=CONTROL_TAG: la vuelta es del grupo de control, que tiene sus propias pausas."""
        journal(e | {"lab": True}, strategy=variant)
        key = e["sym"] if variant is None else f"{e['sym']}#{variant}"
        n = self.cfg.get("pause_window", 15)
        dq = self.recent.setdefault(key, deque(maxlen=n))
        dq.append(e["pnl"])
        kinds = self.recent_kinds.setdefault(key, deque(maxlen=self.cfg.get("fast_pause_window", 6)))
        kinds.append(e.get("kind"))
        fast = sum(k == "stop" for k in kinds) >= self.cfg.get("fast_pause_stops", 3)
        if (len(dq) == n and sum(dq) < 0) or fast:
            kinds.clear()
            self.paused[key] = time.time() + self.cfg.get("pause_hours", 24) * 3600
            dq.clear()
            save_state("lab_paused.json", self.paused)
            log.info("laboratorio: %s pausado %s h (últimas %s vueltas pierden)", key,
                     self.cfg.get("pause_hours", 24), n)

    def _book(self, sym, control=False):
        bk = Book(sym, notional=self.base["risk"]["max_position_eur"], maker=self.maker, taker=self.taker,
                  stop_pct=self.base["stop_pct"], min_edge_pct=self.base["min_edge_pct"],
                  max_hold_s=self.base["max_hold_min"] * 60,
                  on_closed=(lambda e: self.on_closed(e, CONTROL_TAG)) if control else self.on_closed,
                  max_vol_1m_pct=None if control else self.base.get("max_vol_1m_pct"),
                  context=lambda: MARKET.snapshot() | {"sel": allocator.status(self.alloc, sym)})
        key = f"{sym}#{CONTROL_TAG}" if control else sym
        if key in self.saved:
            bk.load(self.saved[key])
        return bk

    def promote(self, now=None):
        """Califica los pares con sus vueltas y devuelve los promovidos que se conservan (explotar)."""
        now = now or time.time()
        if not self.cfg.get("allocator", True):
            return []
        c = self.cfg
        sc = allocator.scores(evidence.load(paths.state("trades.jsonl")), STRATEGY["tag"], now,
                              c.get("score_window", 60), c.get("score_min_n", 20), c.get("score_days", 7))
        paused = {s for s in self.paused if self.is_paused(s)}
        self.alloc, keep = allocator.decide(self.alloc, sc, now, c.get("keep_max", 6), exclude=self.main | paused)
        save_state("allocator.json", self.alloc)
        return keep

    def reselect(self):
        promoted = self.promote()
        picked = select_lab(self.client, self.cfg, self.main | set(promoted) |
                            {s for s in self.paused if self.is_paused(s)})
        keep = {s for s, b in self.books.items() if b.state == "long"} | \
            {s for s, b in self.control.items() if b.state == "long"}   # no se abandonan posiciones
        names = promoted + [s for s, _ in picked][:max(0, self.cfg["max_symbols"] - len(promoted))]
        for s in list(self.books):
            if s not in names and s not in keep:
                self.saved[s] = self.books.pop(s).to_dict()
                if s in self.control:
                    self.saved[f"{s}#{CONTROL_TAG}"] = self.control.pop(s).to_dict()
        for s in names:
            if s not in self.books:
                self.books[s] = self._book(s)
                self.seen[s] = set()
            if self.cfg.get("control_group", True) and s not in self.control:
                self.control[s] = self._book(s, control=True)
        self.order = list(self.books)
        self.selected_at = time.time()
        log.info("laboratorio: promovidos %s · explorando %s", promoted, [s for s in names if s not in promoted])

    def step(self):
        if not self.cfg.get("enabled"):
            return
        if time.time() - self.selected_at > self.cfg["reselect_hours"] * 3600:
            try:
                self.reselect()
            except Exception as e:
                log.warning("no se pudo elegir pares de laboratorio: %s", type(e).__name__)
                self.selected_at = time.time() - self.cfg["reselect_hours"] * 3600 + 600
        syms = []
        for _ in range(min(self.cfg["per_loop"], len(self.order))):
            sym = self.order[self.i % len(self.order)]
            self.i += 1
            bk, ck = self.books[sym], self.control.get(sym)
            main_off = self.is_paused(sym) and bk.state == "flat"
            ctrl_off = ck is None or (self.is_paused(f"{sym}#{CONTROL_TAG}") and ck.state == "flat")
            if main_off:
                bk.px, bk.queue = None, None                     # pausado: no abre; si estaba comprado, sale
            if ck is not None and ctrl_off:
                ck.px, ck.queue = None, None
            if not (main_off and ctrl_off):
                syms.append(sym)
        data = fetch_many(self.client, syms)
        for sym in syms:
            bk = self.books[sym]
            try:
                if isinstance(data[sym], Exception):
                    raise data[sym]
                bt, trades = data[sym]
                new = fresh_trades(trades, self.seen[sym])
                for b in (bk, self.control.get(sym)):
                    if b is None or (b is not bk and self.is_paused(f"{sym}#{CONTROL_TAG}") and b.state == "flat") \
                            or (b is bk and self.is_paused(sym) and b.state == "flat"):
                        continue
                    apply_trades(b, new)                  # primero, contra la orden que estaba puesta
                    b.on_book(float(bt["bidPrice"]), float(bt["bidQty"]), float(bt["askPrice"]), float(bt["askQty"]))
                if len(self.seen[sym]) > 3000:
                    self.seen[sym] = set(sorted(self.seen[sym])[-1000:])
            except Exception as e:
                log.warning("laboratorio %s: %s", sym, type(e).__name__)

    def save(self):
        if self.books:
            save_state("lab_books.json", self.saved | {s: b.to_dict() for s, b in self.books.items()}
                       | {f"{s}#{CONTROL_TAG}": b.to_dict() for s, b in self.control.items()})

    def status(self):
        out = []
        for b in self.books.values():
            c = self.control.get(b.sym)
            sc = (self.alloc.get("scores") or {}).get(b.sym) or {}
            out.append(b.mark() | {"paused": self.is_paused(b.sym), "vol_1m_pct": b.vol_1m(), "er": b.trend()[0],
                                   "sel": allocator.status(self.alloc, b.sym), "score": sc.get("score"),
                                   "control": {"pnl_eur": c.mark()["pnl_eur"], "roundtrips": c.rt} if c else None})
        return out


def step(gate, client, cfg, seen, last_ok, errors):
    """Un ciclo: datos de cada par, modelo de cola y pedido de reinicio. Devuelve "restart" si hay que salir."""
    data = fetch_many(client, list(gate.books) + ["BTCUSDT"])
    if not isinstance(data.get("BTCUSDT"), Exception):
        MARKET.update(data["BTCUSDT"][0])                   # clima general (no es un libro operado)
    for x, bk in gate.books.items():
        try:
            if isinstance(data[x], Exception):
                raise data[x]
            bt, trades = data[x]
            feed(bk, trades, seen[x])          # primero, contra la orden que estaba puesta
            bk.on_book(float(bt["bidPrice"]), float(bt["bidQty"]), float(bt["askPrice"]), float(bt["askQty"]))
            if len(seen[x]) > 5000:
                seen[x] = set(sorted(seen[x])[-2000:])
            last_ok[x] = time.time()
        except Exception as e:
            errors.append(time.time())
            log.warning("error de datos %s: %s", x, type(e).__name__)
        if time.time() - last_ok[x] > cfg["stale_data_s"] and bk.state == "flat" and bk.px is not None:
            bk.px, bk.queue = None, None
            log.warning("datos viejos en %s: se cancela la compra pendiente", x)
    restart = paths.state("RESTART")
    if restart.exists():                             # pedido del actualizador (R-13)
        save_state("paper_books.json", {x: b.to_dict() for x, b in gate.books.items()})
        restart.unlink()
        log.info("reinicio controlado solicitado: estado guardado, saliendo")
        return "restart"
    return None


if __name__ == "__main__":
    try:
        main()
    except Exception:
        try:
            setup_logging()
        except Exception:
            pass
        log.exception("el agente se detuvo por un error al arrancar o fatal")
        raise
