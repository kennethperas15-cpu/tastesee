# 🥮 Taste & See — warm cinnamon buns, on schedule

Online ordering + business analytics + **Bake Pool** (unique feature).

## Unique feature: 🔥 Bake Pool
Timed bake batches (08:00 / 12:30 / 17:00). Customers claim buns in a shared batch:
- **15% off** vs solo order
- **Guaranteed warm** pickup (±10 min or free glaze)
- Kitchen bakes pools **together** → less energy, less waste, predictable queue

Why it wins: group-buying urgency + batch-kitchen efficiency + a reason to return 3× daily.

## Stack (as requested)
- **PyScript** — pricing math, craving predictor, 7-day forecast run as Python in the browser (`py/`, inline `<script type="py">`). JS fallbacks keep the app working if WASM is blocked.
- **Supabase** — Postgres persistence (`supabase/schema.sql`). Falls back to localStorage when keys are absent, so the demo runs with zero setup.

## Run (2 min, no install)
```powershell
cd "C:\kazu\taste&see"
python -m http.server 8000
# open http://localhost:8000/index.html  (store)
# open http://localhost:8000/admin.html  (analytics)
```
> `file://` also works, but http server is recommended for PyScript.

## Connect Supabase (optional, 5 min)
1. Create project at supabase.com → SQL Editor → paste + run `supabase/schema.sql`.
2. Project Settings → API → copy URL + `anon` key.
3. Store → **Settings** → paste keys → Save. Mode badge flips to `supabase mode`.

## Analytics / predictions
`py/analytics.py` + Admin dashboard:
- 7-day demand forecast: `forecast = (7-day avg + trend × days_ahead) × weekday_factor`, safety ×1.05, ±15% band
- Revenue estimate, bake plan per day, weekend staffing tip, waste advice
- Peak hours, best sellers, pool attach rate, order-state pipeline

## Flow
Store: menu → customize → cart → join pool (−15%) → checkout (mock pay, pickup/delivery) → tracking.
Admin: KPIs → charts → forecast → pools → best sellers → order status buttons.
