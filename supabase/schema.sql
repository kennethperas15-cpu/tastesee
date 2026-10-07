-- Taste & See — Supabase schema
-- Paste this into Supabase SQL Editor and run.
-- Requires pgcrypto for uuid generation (enabled by default).

create extension if not exists "pgcrypto";

-- PRODUCTS
create table if not exists products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text default '',
  price_cents int not null check (price_cents >= 0),
  emoji text default '🥯',
  category text default 'classic',
  is_active boolean default true,
  stock_daily int default 60,
  flavor_tags text[] default '{}',
  created_at timestamptz default now()
);

-- BAKE POOLS (unique feature)
create table if not exists bake_pools (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  flavor_focus text default 'mixed',
  target_qty int not null default 12,
  joined_qty int not null default 0,
  slot_time timestamptz not null,
  status text not null default 'filling'
    check (status in ('filling','locked','baking','ready','done')),
  discount_pct int default 15,
  created_at timestamptz default now()
);

-- ORDERS
create table if not exists orders (
  id uuid primary key default gen_random_uuid(),
  customer_name text not null,
  phone text default '',
  kind text not null default 'pickup' check (kind in ('pickup','delivery')),
  address text default '',
  status text not null default 'pending'
    check (status in ('pending','baking','ready','out_for_delivery','completed','cancelled')),
  subtotal_cents int not null default 0,
  discount_cents int not null default 0,
  total_cents int not null default 0,
  pool_id uuid references bake_pools(id) on delete set null,
  is_pool_order boolean default false,
  estimated_ready_at timestamptz,
  created_at timestamptz default now()
);

-- ORDER ITEMS
create table if not exists order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  product_name text not null,
  qty int not null check (qty > 0),
  unit_price_cents int not null,
  customizations jsonb default '{}'
);

-- POOL PARTICIPANTS
create table if not exists pool_participants (
  id uuid primary key default gen_random_uuid(),
  pool_id uuid not null references bake_pools(id) on delete cascade,
  customer_name text not null,
  qty int not null default 1,
  order_id uuid references orders(id) on delete set null,
  created_at timestamptz default now()
);

-- Enable RLS + open read, authenticated write (simple for MVP).
-- Tighten later with Supabase Auth if needed.
alter table products enable row level security;
alter table bake_pools enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table pool_participants enable row level security;

drop policy if exists "public read" on products;
create policy "public read" on products for select using (true);
drop policy if exists "public read pools" on bake_pools;
create policy "public read pools" on bake_pools for select using (true);
drop policy if exists "public read orders" on orders;
create policy "public read orders" on orders for select using (true);
drop policy if exists "public insert orders" on orders;
create policy "public insert orders" on orders for insert with check (true);
drop policy if exists "public update orders" on orders;
create policy "public update orders" on orders for update using (true);
drop policy if exists "public read items" on order_items;
create policy "public read items" on order_items for select using (true);
drop policy if exists "public insert items" on order_items;
create policy "public insert items" on order_items for insert with check (true);
drop policy if exists "public all pools write" on bake_pools;
create policy "public all pools write" on bake_pools for insert with check (true);
drop policy if exists "public pool update" on bake_pools;
create policy "public pool update" on bake_pools for update using (true);
drop policy if exists "public read participants" on pool_participants;
create policy "public read participants" on pool_participants for select using (true);
drop policy if exists "public insert participants" on pool_participants;
create policy "public insert participants" on pool_participants for insert with check (true);
