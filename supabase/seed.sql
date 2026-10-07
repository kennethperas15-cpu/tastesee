-- Taste & See: currently available flavours and today's bake pools.
-- Safe to rerun; legacy flavours are retained but deactivated.

update products
set name = 'Classic',
    description = 'Soft, buttery dough with our signature cinnamon swirl.',
    price_cents = 9500, emoji = '🌀', category = 'classic',
    stock_daily = 80, is_active = true
where lower(name) in ('classic cinnamon swirl', 'classic');

update products
set name = 'Tiramisu',
    description = 'Espresso-kissed cream and a cocoa finish.',
    price_cents = 14500, emoji = '☕', category = 'signature',
    stock_daily = 40, is_active = true
where lower(name) = 'tiramisu';

update products
set name = 'Biscoff',
    description = 'Caramelized biscuit spread with a golden crunch.',
    price_cents = 13500, emoji = '🍪', category = 'signature',
    stock_daily = 40, is_active = true
where lower(name) = 'biscoff';

update products
set name = 'Oreo',
    description = 'Cookies-and-cream filling with a chocolate crumble.',
    price_cents = 12500, emoji = '🍫', category = 'signature',
    stock_daily = 40, is_active = true
where lower(name) = 'oreo';

update products
set is_active = false
where name not in ('Classic', 'Tiramisu', 'Biscoff', 'Oreo');

insert into products (name, description, price_cents, emoji, category, stock_daily)
select v.name, v.description, v.price_cents, v.emoji, 'signature', v.stock_daily
from (values
  ('Classic', 'Soft, buttery dough with our signature cinnamon swirl.', 9500, '🌀', 80),
  ('Tiramisu', 'Espresso-kissed cream and a cocoa finish.', 14500, '☕', 40),
  ('Biscoff', 'Caramelized biscuit spread with a golden crunch.', 13500, '🍪', 40),
  ('Oreo', 'Cookies-and-cream filling with a chocolate crumble.', 12500, '🍫', 40)
) as v(name, description, price_cents, emoji, stock_daily)
where not exists (select 1 from products p where p.name = v.name);

update bake_pools
set flavor_focus = 'Classic · Tiramisu · Biscoff · Oreo'
where slot_time >= date_trunc('day', now());

insert into bake_pools (title, flavor_focus, target_qty, slot_time)
select v.title, v.flavor_focus, v.target_qty, CURRENT_DATE + v.slot_time
from (values
  ('Morning Warm Batch', 'Classic · Tiramisu · Biscoff · Oreo', 12, time '08:00'),
  ('Lunch Melt Batch', 'Classic · Tiramisu · Biscoff · Oreo', 16, time '12:30'),
  ('Sunset Cinna Batch', 'Classic · Tiramisu · Biscoff · Oreo', 20, time '17:00')
) as v(title, flavor_focus, target_qty, slot_time)
where not exists (
  select 1 from bake_pools p
  where p.slot_time >= date_trunc('day', now())
);
