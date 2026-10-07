"""Shared catalogue + demo data. Imported by store.py and analytics.py via PyScript fetch."""
from __future__ import annotations

PRODUCTS = [
    {"id": "classic", "name": "Classic Cinnamon Swirl", "price": 4.50, "emoji": "🌀",
     "desc": "Brioche, Ceylon cinnamon, brown-butter glaze.", "tags": ["bestseller"], "stock": 80},
    {"id": "pecan", "name": "Sticky Pecan Caramel", "price": 5.80, "emoji": "🍯",
     "desc": "Sea-salt caramel, toasted pecans, served warm.", "tags": ["premium"], "stock": 40},
    {"id": "cardamom", "name": "Cardamom Morning Bun", "price": 4.90, "emoji": "🌿",
     "desc": "Swedish-style, cardamom sugar, light icing.", "tags": ["light"], "stock": 50},
    {"id": "choc", "name": "Chocolate Babka Bun", "price": 5.20, "emoji": "🍫",
     "desc": "Dark chocolate swirl, cocoa-nib crunch.", "tags": ["kids"], "stock": 45},
    {"id": "apple", "name": "Apple Pie Bun", "price": 5.50, "emoji": "🍎",
     "desc": "Caramelized apple, oat crumble, cider glaze.", "tags": ["seasonal"], "stock": 35},
    {"id": "vegan", "name": "Vegan Oatmilk Cinnamon", "price": 4.80, "emoji": "🌱",
     "desc": "Plant-based, oatmilk icing, same gooey center.", "tags": ["vegan"], "stock": 40},
    {"id": "ccfrost", "name": "Cream Cheese Frost Deluxe", "price": 5.90, "emoji": "🧁",
     "desc": "Double frosting, vanilla bean, extra cinnamon dust.", "tags": ["bestseller", "premium"], "stock": 50},
    {"id": "pumpkin", "name": "Pumpkin Spice (Limited)", "price": 6.10, "emoji": "🎃",
     "desc": "Limited drop. Pumpkin custard, spice sugar.", "tags": ["limited"], "stock": 24},
]

SIZES = {"Regular": 1.0, "Large (+$1.20)": 1.0, "Mini Box x4": 4.0}
SIZE_UPCHARGE = {"Regular": 0.0, "Large (+$1.20)": 1.20, "Mini Box x4": 0.0}
ICINGS = ["Brown-butter glaze", "Cream cheese", "Oatmilk (vegan)", "No icing", "Extra (+$0.60)"]
TOPPINGS = ["None", "Pecans (+$0.80)", "Choc chips (+$0.70)", "Apple crumble (+$0.80)", "Cinnamon dust (free)"]
TOPPING_PRICE = {"None": 0.0, "Pecans (+$0.80)": 0.8, "Choc chips (+$0.70)": 0.7,
                 "Apple crumble (+$0.80)": 0.8, "Cinnamon dust (free)": 0.0}


def unit_price(base: float, size: str, icing: str, topping: str) -> float:
    p = base + SIZE_UPCHARGE.get(size, 0.0) + TOPPING_PRICE.get(topping, 0.0)
    if icing == "Extra (+$0.60)":
        p += 0.60
    if size == "Mini Box x4":
        p = base * 3.4  # bundle discount
    return round(p, 2)
