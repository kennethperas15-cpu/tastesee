# Backend — Supabase

This project has no separate API server. The browser talks to Supabase, and all
ordering rules are enforced by Postgres functions in [`supabase/schema.sql`](supabase/schema.sql).
That file is the idempotent migration: run it in the Supabase SQL editor for a
fresh project or after pulling these changes.

## Ordering / slot / delivery-notice module

### Database objects

| Object | Purpose |
| --- | --- |
| `store_settings` | One row holding `slot_capacity` (default **80**, `CHECK >= 60`) and the optional `delivery_notice` text. |
| `orders.box_count` | Boxes in the transaction, `CHECK (box_count BETWEEN 1 AND 10)`. |
| `orders.order_day` | Asia/Manila calendar day used by the duplicate guard. |
| `orders.device_key`, `device_model` | Hashed device signature and a readable phone/unit label. |
| `orders.location_key`, `location_source`, `client_ip` | Location fingerprint (delivery pin, address, or IP) and its source. |
| `orders_device_location_day_unique` | Hard unique index on `(device_key, location_key, order_day)` for non-cancelled orders. |

### RPCs ("route handlers")

| RPC | Who can call it | What it does |
| --- | --- | --- |
| `get_slot_status()` | anon + authenticated | Returns capacity, used/remaining boxes for today, and the delivery notice. |
| `check_order_gateway(p_box_count, p_device_key, p_location_key)` | authenticated | Read-only preflight: quantity, slots, duplicate device+location. Returns `{allowed, code, message, remaining}`. |
| `create_order(...)` | authenticated customers | Authoritative write. Repeats every check under an advisory lock before inserting. |
| `update_slot_capacity(p_capacity)` | **admin / owner only** | Validates `60 <= capacity <= 1000`, then updates the singleton settings row. |
| `update_delivery_notice(p_notice)` | **admin / owner only** | Stores a notice of up to 240 characters. |

`owner` is a superset of `admin` through `has_staff_role()`; the admin dashboard
accepts both roles.

### Validation order inside `create_order`

1. Signed-in, non-staff customer.
2. Order shape, delivery coordinates/fee, subtotal.
3. `1 <= box_count <= 10` and `box_count == sum(item quantities)`; each line `1..10`.
4. Discount and total arithmetic.
5. Advisory lock for the day, then slot capacity check.
6. Duplicate `(device_key, location_key, order_day)` check.
7. Insert order + items. The unique index is the final race-condition guard.

### Frontend split

- **Step 1 — flavour customisation:** `frontend/index.html` menu, cart and box
  slots. It only knows about products and quantities.
- **Step 2 — checkout gateway:** `frontend/js/checkout-gateway.js` owns quantity
  limits, slot status, device/location capture, duplicate preflight, and the
  `create_order` call. It receives a finished order snapshot and never reads the
  catalogue or cart state.
- **Admin / owner:** `frontend/admin.html` + `frontend/js/db.js` expose capacity
  and delivery-notice settings.

### Applying the migration

```sql
-- Supabase dashboard → SQL Editor → paste and run:
-- backend/supabase/schema.sql
```

The script is safe to rerun. New columns are added with `IF NOT EXISTS`, the
settings row is upserted, and existing orders are backfilled with their real
`order_day` and item-based `box_count`.
