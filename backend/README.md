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
| `orders.box_count` | Number of 4-bun boxes in the transaction, `CHECK (box_count BETWEEN 1 AND 10)`. |
| `order_items.qty` | Buns of one flavour, `CHECK (qty BETWEEN 1 AND 40)`; the order total must equal `box_count * 4`. |
| `orders.order_day` | Asia/Manila calendar day used by the duplicate guard. |
| `orders.device_key`, `device_model` | Hashed phone/unit signature and a readable phone/unit label. |
| `orders.location_key`, `location_source`, `client_ip` | Location fingerprint (delivery address, optional pin, or IP) and its source. |
| `orders_device_location_day_unique` | Hard unique index on `(device_key, location_key, order_day)` for non-cancelled orders. |

### RPCs ("route handlers")

| RPC | Who can call it | What it does |
| --- | --- | --- |
| `get_slot_status()` | **admin / owner only** | Returns capacity, used/remaining boxes for today, and the delivery notice. Customers never see these counts. |
| `get_delivery_notice()` | anon + authenticated | Returns only the admin-written checkout notice; carries no slot numbers. |
| `check_order_gateway(p_box_count, p_device_key, p_location_key)` | authenticated | Read-only preflight: box count, slots, duplicate device+location. Returns `{allowed, code, message}` with no inventory numbers. |
| `create_order(...)` | authenticated customers | Authoritative write. Repeats every check under an advisory lock before inserting. |
| `update_slot_capacity(p_capacity)` | **admin / owner only** | Validates `60 <= capacity <= 1000`, then updates the singleton settings row. |
| `update_delivery_notice(p_notice)` | **admin / owner only** | Stores a notice of up to 240 characters. |

`owner` is a superset of `admin` through `has_staff_role()`; the admin dashboard
accepts both roles.

### Validation order inside `create_order`

1. Signed-in, non-staff customer.
2. Order shape, delivery address, subtotal.
3. `1 <= box_count <= 10`; total bun quantity must equal `box_count * 4`; each line `1..40`.
4. Discount (`₱10` per 4 buns) and total arithmetic.
5. Advisory lock for the day, then slot capacity check (`sum(box_count)`).
6. Duplicate `(device_key, location_key, order_day)` check.
7. Insert order + items. The unique index is the final race-condition guard.

Delivery is not fulfilled in-house: `delivery_fee_cents` must be `0`, and the
customer books Grab/Lalamove/Maxim directly. Pickup is strictly 10:00 AM – 2:00 PM.

### Frontend split

- **Step 1 — flavour customisation:** `frontend/index.html` menu and box builder.
  Every box has exactly 4 slots, one box is shown by default, and
  "+ Add Another Box" goes up to 10 boxes. This step knows only about products
  and slots.
- **Step 2 — checkout gateway:** `frontend/js/checkout-gateway.js` owns box
  limits, slot capacity, delivery policy, device/location capture, duplicate
  preflight, and the `create_order` call. It receives a finished order snapshot
  and never reads the catalogue or box state.
- **Admin / owner:** `frontend/admin.html` + `frontend/js/db.js` are the only
  place that shows remaining daily slots and the capacity/notice controls.

### Applying the migration

```sql
-- Supabase dashboard → SQL Editor → paste and run:
-- backend/supabase/schema.sql
```

The script is safe to rerun. New columns are added with `IF NOT EXISTS`, the
settings row is upserted, and existing orders are backfilled with their real
`order_day` and a 4-bun-per-box `box_count`. The order-update guard trigger is
dropped before the backfills and recreated afterwards, so running the SQL editor
migration does not fail with "A staff role is required to update an order".
