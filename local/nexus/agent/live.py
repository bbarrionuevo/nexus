"""Ejecución REAL en MEXC (Fase 6) para los pares que el dueño autorizó en ESTA PC.

La estrategia es la misma que en paper (`Book`: compra maker en el mejor bid, venta maker en
max(ask, piso), stop y tiempo máximo a mercado). Lo que cambia es que los llenados vienen del
exchange y no de un modelo. El repositorio nunca habilita el modo real (`live: false`, el CI lo
exige): solo lo habilita `python -m nexus.agent.authorize`, que escribe una persona en la PC, con
capital, pares y vencimiento (R-02).

Protecciones:
- R-05 Estado de orden desconocido (error de red al enviar o cancelar): el par no envía nada más
  hasta conciliar consultando la orden por su ID propio. Al arrancar se concilia la orden guardada,
  se cancelan órdenes propias abiertas y se compara el saldo con la posición esperada; si no coincide,
  el par queda BLOQUEADO hasta revisión humana.
- R-06 ID propio determinista (`nx<seq><par>`), guardado ANTES de enviar.
- R-08 Rechazos del exchange: no reintenta a ciegas; 5 seguidos bloquean el par.
- R-10 Diario de órdenes con hash encadenado y PnL real calculado con las ejecuciones del exchange.
- R-16 KILL: nivel 1 (archivo vacío) no abre posiciones y cancela compras; "2" cancela todas las
  órdenes; "3" cancela y vende las posiciones a mercado.
El riesgo real tiene su propio estado (`risk_real.json`): el paper no consume el límite diario real.
"""
import hashlib
import json
import logging
import math
import time

from .. import paths
from ..live_paper_maker import Book

log = logging.getLogger("nexus.live")
AUTH_FILE, STATE_FILE, ORDERS_LOG, REAL_TRADES = "live_auth.json", "live_books.json", "orders.jsonl", "real_trades.jsonl"
UNBLOCK_FILE = "live_unblock.json"                # pedido humano de desbloqueo (authorize --desbloquear)
CALIBRATION_MAX_EUR, MAX_DAYS = 20.0, 7          # Fase 6a: tope de capital y de vigencia de una autorización
MAX_REJECTS, UNKNOWN_BLOCK_S, BALANCE_TOL_USDT = 5, 120, 0.5
ENDED = ("FILLED", "CANCELED", "PARTIALLY_CANCELED", "REJECTED", "EXPIRED")


def authorization(now=None):
    """Autorización local vigente o None. Solo la escribe una persona con `nexus.agent.authorize`."""
    now = now or time.time()
    a = paths.read_json(paths.state(AUTH_FILE), None)
    if not isinstance(a, dict) or not a.get("symbols") or a.get("expires", 0) <= now:
        return None
    if not 0 < float(a.get("capital_eur", 0)) <= CALIBRATION_MAX_EUR or a["expires"] - a.get("ts", 0) > MAX_DAYS * 86400:
        return None
    return a


def kill_level():
    p = paths.kill_file()
    if not p.exists():
        return 0
    t = p.read_text(encoding="utf-8", errors="ignore").strip()
    return 3 if t.startswith("3") else 2 if t.startswith("2") else 1


class OrderLog:
    """Diario de órdenes solo-agregado con hash encadenado: borrar o editar una línea rompe la cadena."""

    def __init__(self, path=None):
        self.path = path or paths.state(ORDERS_LOG)
        self.prev = "0" * 64
        if self.path.exists():
            lines = self.path.read_text(encoding="utf-8").splitlines()
            if lines:
                self.prev = json.loads(lines[-1]).get("h", self.prev)

    def write(self, entry):
        body = json.dumps(entry, sort_keys=True, default=str)
        h = hashlib.sha256((self.prev + body).encode()).hexdigest()
        with open(self.path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry | {"h": h}, sort_keys=True, default=str) + "\n")
        self.prev = h


def verify_chain(path):
    """True si ninguna línea del diario de órdenes fue alterada."""
    prev = "0" * 64
    for line in path.read_text(encoding="utf-8").splitlines():
        e = json.loads(line)
        h = e.pop("h")
        if hashlib.sha256((prev + json.dumps(e, sort_keys=True, default=str)).encode()).hexdigest() != h:
            return False
        prev = h
    return True


class Rules:
    """Precisión y mínimos del par según exchangeInfo de MEXC. Si falta algo, el par no opera."""

    def __init__(self, info, symbol):
        s = next(x for x in info["symbols"] if x["symbol"] == symbol)
        self.base = s["baseAsset"]
        self.price_dp, self.qty_dp = int(s["quotePrecision"]), int(s["baseAssetPrecision"])
        self.min_quote = max(float(s.get("quoteAmountPrecision") or 0), 1.0)
        types = s.get("orderTypes") or []
        if "LIMIT_MAKER" not in types or "MARKET" not in types or s.get("isSpotTradingAllowed") is False:
            raise ValueError(f"{symbol}: el par no admite LIMIT_MAKER y MARKET en spot")

    def qty(self, x):
        f = 10 ** self.qty_dp
        return math.floor(x * f + 1e-9) / f

    def px(self, x, side):
        """Precio al tick: la compra redondea hacia abajo y la venta hacia arriba (nunca bajo el piso)."""
        f = 10 ** self.price_dp
        return (math.floor(x * f + 1e-9) if side == "BUY" else math.ceil(x * f - 1e-9)) / f

    def fq(self, x):
        return f"{x:.{self.qty_dp}f}"

    def fp(self, x):
        return f"{x:.{self.price_dp}f}"


class LiveBook(Book):
    """Un par operado con dinero real. Book decide el precio deseado (self.px); este libro hace que
    la orden del exchange coincida con ese deseo y toma los llenados de la respuesta del exchange."""

    EXTRA = ("pos_qty", "pos_cost", "rt_qty", "rt_cost", "sold_qty", "sold_quote", "dust", "seq", "order",
             "unknown", "blocked", "rejects")

    def __init__(self, sym, trader, rules, olog, save, now=time.time, **kw):
        super().__init__(sym, now=now, **kw)
        self.trader, self.rules, self.olog, self.save_cb = trader, rules, olog, save
        self.pos_qty = self.pos_cost = self.rt_qty = self.rt_cost = self.sold_qty = self.sold_quote = 0.0
        self.dust, self.seq, self.rejects = 0.0, 0, 0
        self.order = self.unknown = self.blocked = None
        self.entry_allowed = lambda: True

    # -- persistencia ------------------------------------------------------------------------------
    def to_dict(self):
        return {k: getattr(self, k) for k in self.KEYS + self.EXTRA} | {"model": "real"}

    def load(self, d):
        if d.get("model") != "real":
            return False
        for k in self.KEYS + self.EXTRA:
            if k in d:
                setattr(self, k, d[k])
        self.px, self.queue = None, None
        return True

    def mark(self):
        return super().mark() | {"real": True, "pos_qty": self.pos_qty, "dust": self.dust, "blocked": self.blocked,
                                 "unknown": bool(self.unknown), "order": (self.order or {}).get("side")}

    def _log(self, act, **kw):
        self.olog.write({"ts": round(self.now(), 3), "sym": self.sym, "act": act} | kw)

    # -- ciclo ---------------------------------------------------------------------------------------
    def on_trade(self, price, qty, buyer_is_maker):
        """En real los llenados vienen del exchange, no de las operaciones públicas."""

    def on_book(self, b, bq, a, aq):
        if self.unknown:
            self._resolve_unknown()
        elif self.order:
            self._sync()
        lvl = kill_level()
        if self.unknown or self.blocked:
            self.bid, self.ask = b, a
            return
        if lvl >= 2:                                          # R-16 nivel 2 y 3
            self.bid, self.ask = b, a
            if self.order and self.order["type"] != "MARKET":
                self._cancel()
            elif lvl == 3 and self.state == "long" and not self.order:
                self._close(b, self.taker, "kill")
            return
        if self.state == "flat" and not self.entry_allowed():  # autorización vencida o revocada
            self.bid, self.ask, self.px = b, a, None
        else:
            super().on_book(b, bq, a, aq)
        self._place()

    def stale(self):
        """Datos viejos: no dejar una compra puesta a un precio que ya no sabemos si sirve."""
        if self.state == "flat" and self.order and not self.unknown:
            self.px = None
            self._cancel()

    # -- órdenes -----------------------------------------------------------------------------------
    def _place(self):
        if self.unknown or self.blocked:
            return
        side = "BUY" if self.state == "flat" else "SELL"
        o, want = self.order, None if self.px is None else self.rules.px(self.px, side)
        if o:
            if o["type"] == "MARKET":
                return
            if want is None or o["side"] != side or abs(o["px"] - want) > 1e-12:
                self._cancel()                                # la nueva va en el próximo ciclo
            return
        if want is None:
            return
        if side == "BUY":
            qty = self.rules.qty(max(self.notional - self.pos_cost, 0) / want)
        else:
            qty = self.rules.qty(self.pos_qty)
        if qty * want < self.rules.min_quote:
            if side == "SELL":                                # lo que queda no se puede vender: residuo
                self._finish("maker")
            return
        self._new(side, "LIMIT_MAKER", qty, want)

    def _new(self, side, type_, qty, px, kind=None):
        self.seq += 1
        cid = f"nx{self.seq}{self.sym}"[:32]
        self.order = {"cid": cid, "side": side, "type": type_, "px": px, "qty": qty, "ts": self.now(),
                      "exec_qty": 0.0, "exec_quote": 0.0, "kind": kind}
        self.save_cb()                                        # R-06: registrado ANTES de enviar
        self._log("enviar", cid=cid, side=side, type=type_, px=px, qty=qty)
        try:
            self.trader.new_order(self.sym, side, type_, self.rules.fq(qty),
                                  self.rules.fp(px) if px is not None else None, cid)
        except Exception as e:                               # noqa: BLE001 (se clasifica)
            if getattr(e, "status", None):                   # rechazo: resultado conocido
                self.order = None
                self.rejects += 1
                self._log("rechazada", cid=cid, error=str(e)[:200])
                log.warning("real %s: orden rechazada (%s)", self.sym, e)
                if self.rejects >= MAX_REJECTS:
                    self.blocked = f"{self.rejects} rechazos seguidos del exchange: revisar ({str(e)[:120]})"
            else:
                self._set_unknown(cid, e)
            self.save_cb()
            return False
        self.rejects = 0
        self._log("aceptada", cid=cid)
        self.save_cb()
        return True

    def _set_unknown(self, cid, e):
        self.unknown = {"cid": cid, "since": self.now(), "misses": 0}
        self._log("desconocido", cid=cid, error=type(e).__name__)
        log.warning("real %s: resultado desconocido de %s (%s): se concilia antes de seguir", self.sym, cid,
                    type(e).__name__)

    def _resolve_unknown(self):
        u = self.unknown
        try:
            resp = self.trader.get_order(self.sym, u["cid"])
        except Exception as e:                               # noqa: BLE001
            if getattr(e, "not_found", False):
                u["misses"] += 1
                if u["misses"] >= 2 and self.now() - u["since"] >= 3:   # el exchange no la creó
                    self._log("no_existe", cid=u["cid"])
                    self.order, self.unknown = None, None
                    self.save_cb()
            elif self.now() - u["since"] > UNKNOWN_BLOCK_S and not self.blocked:
                self.blocked = f"no se pudo conciliar la orden {u['cid']} en {UNKNOWN_BLOCK_S} s"
            return
        self.unknown = None
        self._log("conciliada", cid=u["cid"], status=resp.get("status"))
        self._apply(resp)

    def _sync(self):
        try:
            self._apply(self.trader.get_order(self.sym, self.order["cid"]))
        except Exception as e:                               # noqa: BLE001
            if getattr(e, "not_found", False) and self.now() - self.order["ts"] > 10:
                self._set_unknown(self.order["cid"], e)      # la teníamos y ya no aparece: conciliar
            else:
                log.warning("real %s: no se pudo consultar la orden (%s)", self.sym, type(e).__name__)

    def _cancel(self):
        cid = self.order["cid"]
        self._log("cancelar", cid=cid)
        try:
            self.trader.cancel_order(self.sym, cid)
        except Exception as e:                               # noqa: BLE001
            if not getattr(e, "status", None):
                self._set_unknown(cid, e)
                self.save_cb()
                return False
        try:                                                  # el estado final dice qué se ejecutó
            self._apply(self.trader.get_order(self.sym, cid))
        except Exception as e:                               # noqa: BLE001
            self._set_unknown(cid, e)
            self.save_cb()
            return False
        return self.order is None

    def _apply(self, resp):
        o = self.order
        if o is None:
            return
        q, quote = float(resp.get("executedQty") or 0), float(resp.get("cummulativeQuoteQty") or 0)
        dq, dquote = q - o["exec_qty"], quote - o["exec_quote"]
        if dq > 0:
            fee = dquote * (self.maker if o["type"] == "LIMIT_MAKER" else self.taker) / 100
            if o["side"] == "BUY":
                self.pos_qty += dq
                self.pos_cost += dquote + fee
            else:
                self.pos_qty = max(self.pos_qty - dq, 0.0)
                self.sold_qty += dq
                self.sold_quote += dquote - fee
            self._log("ejecutada", cid=o["cid"], side=o["side"], qty=dq, quote=round(dquote, 8), fee=round(fee, 8))
        o["exec_qty"], o["exec_quote"] = q, quote
        if resp.get("status") in ENDED:
            self.order = None
            self._ended(o)
        self.save_cb()

    def _ended(self, o):
        ref = self.bid or o["px"] or 0
        if o["side"] == "BUY":
            if self.state == "flat" and self.pos_qty * ref >= self.rules.min_quote:
                self.state, self.qty, self.entry = "long", self.pos_qty, self.pos_cost / self.pos_qty
                self.entry_ts, self.entry_fee = self.now(), 0.0
                self.rt_qty, self.rt_cost = self.pos_qty, self.pos_cost
                er, ret = self.trend()
                self.entry_ctx = {"vol_1m_pct": self.vol_1m(), "er": er, "ret_window_pct": ret} | (
                    self.context() if self.context else {})
                self._log("posicion", qty=self.pos_qty, cost=round(self.pos_cost, 8))
        elif self.pos_qty * ref < self.rules.min_quote:       # vendido todo lo vendible
            self._finish(o.get("kind") or "maker")

    def _close(self, px, fee, kind):
        """Stop, tiempo máximo o KILL 3: vender a mercado lo que haya (Book llama acá)."""
        if self.order:
            if self.order["type"] == "MARKET" or not self._cancel():
                return
        if self.state != "long":
            return
        qty = self.rules.qty(self.pos_qty)
        if qty * px < self.rules.min_quote:
            return self._finish(kind)
        if self._new("SELL", "MARKET", qty, None, kind=kind):
            self._sync()

    def _finish(self, kind):
        """Cierra la vuelta con lo realmente ejecutado. Lo que no se puede vender queda como residuo."""
        sold_cost = self.rt_cost * (self.sold_qty / self.rt_qty) if self.rt_qty else 0.0
        pnl = self.sold_quote - sold_cost
        self.dust += self.pos_qty
        self.rt += 1
        self.wins += pnl > 0
        self.stops += kind == "stop"
        self.timeouts += kind == "timeout"
        self.eq += pnl
        if self.gate:
            self.gate.on_close(pnl, kind != "maker")
        exit_px = self.sold_quote / self.sold_qty if self.sold_qty else None
        self._log("vuelta", kind=kind, pnl=round(pnl, 8), qty=self.sold_qty)
        if self.on_closed:
            self.on_closed({"ts": self.now(), "sym": self.sym, "pnl": round(pnl, 6), "kind": kind, "real": True,
                            "hold_s": round(self.now() - self.entry_ts, 1), "entry": self.entry, "exit": exit_px,
                            "qty": self.sold_qty, "cost": round(sold_cost, 8), "proceeds": round(self.sold_quote, 8),
                            "notional": self.notional} | self.entry_ctx)
        self.state, self.px, self.qty, self.entry = "flat", None, 0.0, 0.0
        self.pos_qty = self.pos_cost = self.rt_qty = self.rt_cost = self.sold_qty = self.sold_quote = 0.0
        self.save_cb()

    # -- arranque y salida -----------------------------------------------------------------------
    def reconcile(self, balances, px):
        """Al arrancar (R-05): concilia la orden guardada, cancela órdenes propias que hayan quedado
        abiertas y compara el saldo del exchange con la posición esperada."""
        if self.order or self.unknown:
            cid = (self.unknown or self.order)["cid"]
            self.unknown = {"cid": cid, "since": self.now() - UNKNOWN_BLOCK_S / 2, "misses": 1}
            self._resolve_unknown()
            if self.order and not self.unknown and self.order["type"] != "MARKET":
                self._cancel()
        try:
            for o in self.trader.open_orders(self.sym):
                cid = o.get("clientOrderId") or ""
                if not cid.startswith("nx"):
                    self.blocked = f"hay una orden abierta que no es de nexus ({cid or o.get('orderId')})"
                elif not self.order or cid != self.order["cid"]:
                    self.trader.cancel_order(self.sym, cid)     # huérfana: el saldo dirá si se ejecutó algo
                    self._log("cancelar_huerfana", cid=cid)
        except Exception as e:                               # noqa: BLE001
            self.blocked = f"no se pudieron leer las órdenes abiertas ({type(e).__name__})"
        self.check_balance(balances, px)

    def check_balance(self, balances, px):
        """Saldo del activo en el exchange vs. posición + residuo que creemos tener. Si no coincide, el
        par queda bloqueado: operar con un estado que no entendemos es justo lo que prohíbe R-05."""
        if self.order or self.unknown or self.blocked:
            return
        held = sum(float(b.get("free") or 0) + float(b.get("locked") or 0)
                   for b in balances if b.get("asset") == self.rules.base)
        expected = self.pos_qty + self.dust
        if px and abs(held - expected) * px > BALANCE_TOL_USDT:
            self.blocked = (f"saldo de {self.rules.base} {held} distinto del esperado {expected}: "
                            "conciliar a mano (no se opera este par)")
            log.error("real %s BLOQUEADO: %s", self.sym, self.blocked)
            self._log("bloqueado", motivo=self.blocked)
        self.save_cb()

    def unblock(self, balances):
        """Pedido del dueño tras revisar el par: se cancela lo nuestro y TODO el saldo del activo pasa a
        residuo no gestionado. El libro arranca de cero: nunca opera sobre una posición que no entiende."""
        try:
            for o in self.trader.open_orders(self.sym):
                if (o.get("clientOrderId") or "").startswith("nx"):
                    self.trader.cancel_order(self.sym, o["clientOrderId"])
        except Exception as e:                               # noqa: BLE001
            log.warning("real %s: desbloqueo pospuesto (%s)", self.sym, type(e).__name__)
            return False
        held = sum(float(b.get("free") or 0) + float(b.get("locked") or 0)
                   for b in balances if b.get("asset") == self.rules.base)
        self._log("desbloqueado", motivo_anterior=self.blocked, residuo=held)
        self.order = self.unknown = self.blocked = None
        self.rejects, self.state, self.px, self.qty, self.entry, self.dust = 0, "flat", None, 0.0, 0.0, held
        self.pos_qty = self.pos_cost = self.rt_qty = self.rt_cost = self.sold_qty = self.sold_quote = 0.0
        self.save_cb()
        return True

    def shutdown(self):
        """Reinicio controlado: no dejar órdenes límite puestas sin nadie que las vigile."""
        if self.order and not self.unknown and self.order["type"] != "MARKET":
            self._cancel()
        self.save_cb()


def journal_real(entry):
    with open(paths.state(REAL_TRADES), "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, default=str) + "\n")


def real_summary(path=None):
    """Resultado real (ejecuciones del exchange): total, por día y criterio de 6a a 6b."""
    from .. import evidence
    p = path or paths.state(REAL_TRADES)
    rows = []
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            try:
                rows.append(json.loads(line))
            except ValueError:
                continue
    st = evidence.stats([t["pnl"] for t in rows])
    first = min((t["ts"] for t in rows), default=None)
    days = (time.time() - first) / 86400 if first else 0.0
    return st | {"daily": evidence.daily(rows), "days": round(days, 2), "by_kind": evidence.by_kind(rows),
                 "pass_6b": days >= 7 and (st.get("total") or 0) > 0}


class Desk:
    """Los libros reales: datos, ciclo, guardado y estado para el tablero."""

    def __init__(self, trader, client, gate, books, olog):
        self.trader, self.client, self.gate, self.books, self.olog = trader, client, gate, books, olog
        self.last_ok = {s: time.time() for s in books}

    def save(self):
        from .maker_agent import save_state
        save_state(STATE_FILE, {s: b.to_dict() for s, b in self.books.items()})

    def check_balances(self):
        """Cada 10 min: el saldo del exchange tiene que coincidir con lo que creemos tener."""
        try:
            bal = self.trader.account().get("balances", [])
        except Exception as e:                               # noqa: BLE001
            log.warning("real: no se pudo leer el saldo (%s)", type(e).__name__)
            return
        for bk in self.books.values():
            bk.check_balance(bal, bk.bid)

    def unblock_requests(self):
        req = paths.state(UNBLOCK_FILE)
        if not req.exists():
            return
        syms = [s for s in (paths.read_json(req, {}).get("symbols") or []) if s in self.books]
        try:
            bal = self.trader.account().get("balances", [])
        except Exception:                                    # noqa: BLE001
            return
        if all(self.books[s].unblock(bal) for s in syms):
            req.unlink()

    def step(self, stale_s):
        self.unblock_requests()
        for s, bk in self.books.items():
            try:
                bt = self.client.book_ticker(s)
                bk.on_book(float(bt["bidPrice"]), float(bt["bidQty"]), float(bt["askPrice"]), float(bt["askQty"]))
                self.last_ok[s] = time.time()
            except Exception as e:                           # noqa: BLE001
                log.warning("real %s: error de ciclo (%s)", s, type(e).__name__)
            if time.time() - self.last_ok[s] > stale_s:
                bk.stale()

    def shutdown(self):
        for bk in self.books.values():
            try:
                bk.shutdown()
            except Exception:                                # noqa: BLE001
                log.exception("real %s: no se pudo cancelar al salir", bk.sym)
        self.save()

    def status(self, auth):
        return {"auth": auth, "books": [b.mark() for b in self.books.values()],
                "risk": self.gate.risk.snapshot(), "risk_block": self.gate.risk.last_reason,
                "kill_level": kill_level(), "real": {k: v for k, v in real_summary().items() if k != "daily"}}
