"""Fuentes públicas (sin API key) de libros top-of-book."""
import requests

S = requests.Session()


def _get(url, **kw):
    r = S.get(url, timeout=15, **kw)
    r.raise_for_status()
    return r.json()


def kraken_book(quotes=("EUR", "USDC", "USD", "BTC", "ETH")):
    """Todos los pares spot de Kraken cuyas dos monedas estén en un universo líquido."""
    pairs = _get("https://api.kraken.com/0/public/AssetPairs")["result"]
    tick = _get("https://api.kraken.com/0/public/Ticker")["result"]
    book = {}
    for k, p in pairs.items():
        if k not in tick or ".d" in k:
            continue
        base, quote = p.get("wsname", "/").split("/") if "wsname" in p else (None, None)
        if not base or quote not in quotes:
            continue
        base = {"XBT": "BTC", "XDG": "DOGE"}.get(base, base)
        quote = {"XBT": "BTC"}.get(quote, quote)
        t = tick[k]
        fee = float(p["fees"][0][1]) if p.get("fees") else 0.4
        book[f"{base}/{quote}"] = (base, quote, float(t["b"][0]), float(t["a"][0]), fee)
    return book


def bitstamp_book(pairs=("btceur", "etheur", "usdceur", "eurceur", "xrpeur", "soleur")):
    out = {}
    for p in pairs:
        try:
            t = _get(f"https://www.bitstamp.net/api/v2/ticker/{p}/")
            out[p[:-3].upper() + "/EUR"] = (float(t["bid"]), float(t["ask"]))
        except Exception:
            pass
    return out


def coinbase_book(pairs=("BTC-EUR", "ETH-EUR", "USDC-EUR", "SOL-EUR", "XRP-EUR")):
    out = {}
    for p in pairs:
        try:
            t = _get(f"https://api.exchange.coinbase.com/products/{p}/ticker")
            out[p.replace("-", "/")] = (float(t["bid"]), float(t["ask"]))
        except Exception:
            pass
    return out


def criptoya(coin, fiat="ARS", vol=100):
    return _get(f"https://criptoya.com/api/{coin}/{fiat}/{vol}")
