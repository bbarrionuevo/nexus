"""Gestor de riesgo del agente: límites duros que ninguna estrategia puede saltear."""
import time
from pathlib import Path


class RiskHalt(Exception):
    pass


class RiskManager:
    def __init__(self, cfg, kill_file="state/KILL"):
        self.max_notional = cfg["max_notional_eur"]
        self.daily_loss = cfg["daily_loss_limit_eur"]
        self.max_stops = cfg["max_consecutive_stops"]
        self.max_orders_min = cfg["max_orders_per_minute"]
        self.kill_file = Path(kill_file)
        self.day, self.pnl_day, self.stops_row, self.orders = time.strftime("%F"), 0.0, 0, []

    def check(self, notional):
        if self.kill_file.exists():
            raise RiskHalt("interruptor de emergencia activo (state/KILL)")
        if time.strftime("%F") != self.day:
            self.day, self.pnl_day, self.stops_row = time.strftime("%F"), 0.0, 0
        if notional > self.max_notional:
            raise RiskHalt(f"nocional {notional} > máximo {self.max_notional}")
        if self.pnl_day <= -self.daily_loss:
            raise RiskHalt(f"pérdida diaria {self.pnl_day:.2f} alcanzó el límite")
        if self.stops_row >= self.max_stops:
            raise RiskHalt(f"{self.stops_row} stops seguidos: pausa por régimen adverso")
        now = time.time()
        self.orders = [t for t in self.orders if now - t < 60] + [now]
        if len(self.orders) > self.max_orders_min:
            raise RiskHalt("demasiadas órdenes por minuto")

    def on_close(self, pnl, was_stop):
        self.pnl_day += pnl
        self.stops_row = self.stops_row + 1 if was_stop else 0
