"""Shared catalogue + demo data. Imported by store.py and analytics.py via PyScript fetch."""
from __future__ import annotations

PRODUCTS = [
    {"id": "classic", "name": "Classic", "price": 95.0, "emoji": "🌀",
     "desc": "Soft, buttery dough with our signature cinnamon swirl.", "tags": ["original"], "stock": 80},
    {"id": "tiramisu", "name": "Tiramisu", "price": 145.0, "emoji": "☕",
     "desc": "Espresso-kissed cream with a dreamy cocoa finish.", "tags": ["signature"], "stock": 40},
    {"id": "biscoff", "name": "Biscoff", "price": 135.0, "emoji": "🍪",
     "desc": "Caramelized biscuit spread and a golden crunch.", "tags": ["signature"], "stock": 40},
    {"id": "oreo", "name": "Oreo", "price": 125.0, "emoji": "🍫",
     "desc": "Cookies-and-cream filling with chocolate crumble.", "tags": ["signature"], "stock": 40},
]

SIZES = {"Regular": 1.0, "Large (+₱30)": 1.0, "Mini Box x4": 4.0}
SIZE_UPCHARGE = {"Regular": 0.0, "Large (+₱30)": 30.0, "Mini Box x4": 0.0}
ICINGS = ["Classic glaze", "Cream cheese", "No icing", "Extra cream (+₱15)"]
TOPPINGS = ["None", "Crushed Oreo (+₱15)", "Biscoff crumble (+₱15)", "Cocoa dust (free)"]
TOPPING_PRICE = {
    "None": 0.0,
    "Crushed Oreo (+₱15)": 15.0,
    "Biscoff crumble (+₱15)": 15.0,
    "Cocoa dust (free)": 0.0,
}


def unit_price(base: float, size: str, icing: str, topping: str) -> float:
    price = base + SIZE_UPCHARGE.get(size, 0.0) + TOPPING_PRICE.get(topping, 0.0)
    if icing == "Extra cream (+₱15)":
        price += 15.0
    if size == "Mini Box x4":
        price = base * 3.4
    return round(price, 2)
