<p align="center"><img src="./assets/logo.png" alt="Taste & See logo" width="180" /></p>

# Taste & See — fresh buns, baked with love

Responsive Philippine-peso storefront for four fresh flavours: **Classic, Tiramisu, Biscoff, and Oreo**. Includes online ordering, shared Bake Pools, an admin dashboard, and a separate baker production queue.

## Store experience
- Scroll-triggered reveal animation and a live reading-progress indicator, with reduced-motion support.
- PHP prices and a concise four-flavour menu.
- Timed Bake Pools at 08:00 / 12:30 / 17:00, with 15% off.
- Order lookup requires the checkout name and the first eight characters of the order number.

## Stack
- **PyScript** — pricing math and in-browser business logic (`py/`, inline `<script type="py">`). JS fallbacks keep the app working if WASM is blocked.
- **Supabase** — Postgres persistence (`supabase/schema.sql`). Falls back to localStorage for storefront demos when keys are absent.

## Run locally
```powershell
cd "C:\kazu\taste&see"
python -m http.server 8000
# open http://localhost:8000/index.html
```
> `file://` also works, but an HTTP server is recommended for PyScript.

## Connect Supabase and provision staff
1. Create a Supabase project. In the SQL Editor, run `supabase/schema.sql`, then `supabase/seed.sql`.
2. Copy the project URL and publishable/anon key from **Project Settings → API**. Add them to the connection settings in the storefront, or configure `TASTESEE_SUPABASE_URL` and `TASTESEE_SUPABASE_ANON_KEY` in the HTML files.
3. In **Authentication → Users**, create or invite staff accounts. Disable public sign-ups if they are not needed.
4. Assign each account a role using the SQL Editor, replacing the email and role:
   ```sql
   insert into public.staff_access (user_id, role)
   select id, 'admin'
   from auth.users
   where email = 'owner@example.com'
   on conflict (user_id) do update set role = excluded.role;
   ```
   Use `'baker'` for baker accounts. Only the owner should manage `staff_access`; staff cannot grant roles to themselves.
5. Staff sign in at `/admin.html` (admin only) or `/baker.html` (bakers and admins). The baker workspace advances orders from pending → baking → ready. Supabase row-level security enforces staff roles; localStorage demo mode does not grant staff access.

## Admin analytics
`/admin.html` requires an assigned admin account. It includes:
- A 7-day demand forecast using moving average, weekday seasonality, and trend.
- Revenue estimates, bake plans, peak hours, best sellers, pool rate, and order status controls.

Payments remain a mock checkout; no card is charged.
