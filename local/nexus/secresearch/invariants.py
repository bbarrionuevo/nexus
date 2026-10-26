"""Etapa C: método de validación por invariantes de un vault ERC-4626, en Python puro.

Modelo de referencia de la contabilidad shares/assets con aritmética ENTERA (como Solidity) y un
verificador de propiedades que recorre una grilla fija y determinista de estados y montos, y devuelve
el PRIMER contraejemplo de cada propiedad (reproducible: mismos datos, mismo resultado).

Propiedades (lo que un vault ERC-4626 correcto debe preservar):
  P1 depositar y rescatar todo no devuelve más de lo depositado (el redondeo no crea valor)
  P2 acuñar shares y rescatarlas no devuelve más de lo pagado
  P3 retirar no deja al usuario con más valor que antes (retirado + lo que le queda ≤ lo que tenía)
  P4 solvencia: lo que todos pueden rescatar no supera los activos del vault
  P5 ataque del primer depositante (donación directa) no le deja ganancia al atacante
  P6 ninguna operación de un usuario baja el valor de los demás (el redondeo favorece al vault)
  P0 ninguna operación revienta (división por cero o estado imposible: en Solidity, un revert que
     puede bloquear depósitos o rescates)

Los estados incluyen pérdidas del vault (precio de la share < 1): sin ellas, acuñar redondeando hacia
abajo o rescatar redondeando hacia arriba no se notan (primera versión del verificador, 26-oct-2026).

Esto DEMUESTRA EL MÉTODO sobre implementaciones de referencia (una correcta y variantes con defectos
conocidos y documentados públicamente). No es un hallazgo sobre ningún protocolo: para eso hace falta
traducir las propiedades a tests de Foundry contra el código EN ALCANCE (etapa D, en la PC del dueño).
"""


def _div(n, d, up):
    return -(-n // d) if up else n // d


class Vault:
    """virtual=True: offset de shares virtuales al estilo OpenZeppelin (+10**offset shares, +1 asset).
    virtual=False: implementación ingenua (1:1 si está vacío). round_*: True = hacia arriba."""

    def __init__(self, virtual=True, offset=0, deposit_up=False, mint_up=True, withdraw_up=True, redeem_up=False):
        self.virtual, self.offset = virtual, offset
        self.r = {"deposit": deposit_up, "mint": mint_up, "withdraw": withdraw_up, "redeem": redeem_up}
        self.assets, self.supply, self.bal = 0, 0, {}

    def to_shares(self, a, up):
        if self.virtual:
            return _div(a * (self.supply + 10 ** self.offset), self.assets + 1, up)
        return a if self.supply == 0 else _div(a * self.supply, self.assets, up)

    def to_assets(self, s, up):
        if self.virtual:
            return _div(s * (self.assets + 1), self.supply + 10 ** self.offset, up)
        return s if self.supply == 0 else _div(s * self.assets, self.supply, up)

    def _add(self, who, s, a):
        self.bal[who] = self.bal.get(who, 0) + s
        self.supply += s
        self.assets += a

    def deposit(self, who, a):
        s = self.to_shares(a, self.r["deposit"])
        self._add(who, s, a)
        return s

    def mint(self, who, s):
        a = self.to_assets(s, self.r["mint"])
        self._add(who, s, a)
        return a

    def withdraw(self, who, a):
        s = self.to_shares(a, self.r["withdraw"])
        if s > self.bal.get(who, 0) or a > self.assets:
            raise ValueError("saldo insuficiente")
        self._add(who, -s, -a)
        return s

    def redeem(self, who, s):
        if s > self.bal.get(who, 0):
            raise ValueError("saldo insuficiente")
        a = self.to_assets(s, self.r["redeem"])
        if a > self.assets:
            raise ValueError("activos insuficientes")
        self._add(who, -s, -a)
        return a

    def donate(self, a):
        self.assets += a                                 # transferencia directa al vault (sin acuñar)

    def lose(self, a):
        self.assets -= min(a, self.assets)               # pérdida de la estrategia (sin quemar shares)

    def value(self, who):
        return self.to_assets(self.bal.get(who, 0), False)


SEEDS, DONATIONS, AMOUNTS = (1, 7, 100, 10 ** 6), (0, 1, 3, 10 ** 5), (1, 2, 3, 9, 1000)
LOSSES = (0, 1, 0.5)                                     # 0.5 = la mitad de los activos
ATTACK_DONATIONS, VICTIM_DEPOSITS = (10, 10 ** 3, 10 ** 6), (10, 10 ** 3, 10 ** 5)


def _state(make, seed, donation, loss=0):
    v = make()
    v.deposit("seed", seed)
    v.donate(donation)
    v.lose(int(v.assets * loss) if isinstance(loss, float) else loss)
    return v


def _others(v, who):
    return {k: v.value(k) for k in v.bal if k != who}


def _grid(make, out, fail, seed, don, loss, a):
    ctx = {"seed": seed, "donation": don, "loss": loss}
    v = _state(make, seed, don, loss)
    s = v.deposit("u", a)
    try:
        got = v.redeem("u", s)
    except ValueError:
        got = 0
    if got > a:
        fail("P1", **ctx, deposited=a, shares=s, redeemed=got)

    v = _state(make, seed, don, loss)
    paid = v.mint("u", a)
    try:
        got = v.redeem("u", a)
    except ValueError:
        got = 0
    if got > paid:
        fail("P2", **ctx, shares=a, paid=paid, redeemed=got)

    v = _state(make, seed, don, loss)
    v.deposit("u", 10 * a + 10)
    before = v.value("u")
    try:
        v.withdraw("u", a)
        if a + v.value("u") > before:
            fail("P3", **ctx, withdrawn=a, before=before, after=v.value("u"))
    except ValueError:
        pass

    v = _state(make, seed, don, loss)
    v.deposit("u", a)
    v.deposit("w", a + 1)
    redeemable = sum(v.value(k) for k in v.bal)
    if redeemable > v.assets:
        fail("P4", **ctx, redeemable=redeemable, assets=v.assets)

    for op in ("deposit", "mint", "withdraw", "redeem"):
        v = _state(make, seed, don, loss)
        v.deposit("u", 10 * a + 10)
        before = _others(v, "u")
        try:
            getattr(v, op)("u", a)
        except ValueError:
            continue
        after = _others(v, "u")
        hurt = {k: (before[k], after[k]) for k in before if after.get(k, 0) < before[k]}
        if hurt:
            fail("P6", **ctx, op=op, amount=a, others_before_after=hurt)


def check(make):
    """{propiedad: None si se cumple en toda la grilla, o el primer contraejemplo}."""
    out = {f"P{i}": None for i in range(7)}

    def fail(p, **ctx):
        if out[p] is None:
            out[p] = ctx

    for seed in SEEDS:
        for don in DONATIONS:
            for loss in LOSSES:
                for a in AMOUNTS:
                    try:
                        _grid(make, out, fail, seed, don, loss, a)
                    except ZeroDivisionError:
                        fail("P0", seed=seed, donation=don, loss=loss, amount=a, error="división por cero")

    for d in ATTACK_DONATIONS:
        for vic in VICTIM_DEPOSITS:
            v = make()
            try:
                v.deposit("atk", 1)
                v.donate(d)
                v.deposit("victim", vic)
                got = v.redeem("atk", v.bal["atk"])
            except ZeroDivisionError:
                fail("P0", donation=d, victim_deposit=vic, error="división por cero")
                continue
            if got - (1 + d) > 0:
                fail("P5", donation=d, victim_deposit=vic, attacker_spent=1 + d, attacker_got=got)
    return out
