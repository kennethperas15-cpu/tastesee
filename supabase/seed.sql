-- Taste & See seed data — run AFTER schema.sql in Supabase SQL Editor.
-- Safe to re-run: inserts only when tables are empty / no pools today.

insert into products (name, description, price_cents, emoji, category, stock_daily)
select * from (values
  ('Classic Cinnamon Swirl', 'Brioche, Ceylon cinnamon, brown-butter glaze.', 450, '🌀', 'classic', 80),
  ('Sticky Pecan Caramel', 'Sea-salt caramel, toasted pecans, served warm.', 580, '🍯', 'premium', 40),
  ('Cardamom Morning Bun', 'Swedish-style, cardamom sugar, light icing.', 490, '🌿', 'classic', 50),
  ('Chocolate Babka Bun', 'Dark chocolate swirl, cocoa-nib crunch.', 520, '🍫', 'classic', 45),
  ('Apple Pie Bun', 'Caramelized apple, oat crumble, cider glaze.', 550, '🍎', 'seasonal', 35),
  ('Vegan Oatmilk Cinnamon', 'Plant-based, oatmilk icing, same gooey center.', 480, '🌱', 'vegan', 40),
  ('Cream Cheese Frost Deluxe', 'Double frosting, vanilla bean, extra cinnamon dust.', 590, '🧁', 'premium', 50),
  ('Pumpkin Spice (Limited)', 'Limited drop. Pumpkin custard, spice sugar.', 610, '🎃', 'limited', 24)
) as v(name, description, price_cents, emoji, category, stock_daily)
where not exists (select 1 from products);

insert into bake_pools (title, flavor_focus, target_qty, slot_time)
select * from (values
  ('Morning Warm Batch', 'classic + cardamom', 12, CURRENT_DATE + time '08:00'),
  ('Lunch Melt Batch', 'pecan + choc', 16, CURRENT_DATE + time '12:30'),
  ('Sunset Cinna Batch', 'mixed + pumpkin', 20, CURRENT_DATE + time '17:00')
) as v(title, flavor_focus, target_qty, slot_time)
where not exists (select 1 from bake_pools where slot_time >= date_trunc('day', now()));
