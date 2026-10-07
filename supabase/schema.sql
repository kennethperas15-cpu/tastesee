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

-- Staff accounts are created in Supabase Auth. The owner assigns roles here;
-- staff cannot grant themselves access.
create table if not exists staff_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin', 'baker')),
  created_at timestamptz not null default now()
);

alter table staff_access enable row level security;
revoke all on public.staff_access from anon, authenticated;
grant select on public.staff_access to authenticated;

create or replace function public.has_staff_role(p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.staff_access
    where user_id = auth.uid() and role = any(p_roles)
  );
$$;

revoke all on function public.has_staff_role(text[]) from public, anon;
grant execute on function public.has_staff_role(text[]) to authenticated;

drop policy if exists "staff read own access" on staff_access;
create policy "staff read own access" on staff_access
  for select to authenticated using (user_id = auth.uid());

-- Public can browse and place orders, but operational data is staff-only.
alter table products enable row level security;
alter table bake_pools enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table pool_participants enable row level security;

drop policy if exists "public read" on products;
create policy "public read" on products for select using (true);
drop policy if exists "admin manage products" on products;
create policy "admin manage products" on products for all to authenticated
  using (public.has_staff_role(array['admin']))
  with check (public.has_staff_role(array['admin']));

drop policy if exists "public read pools" on bake_pools;
create policy "public read pools" on bake_pools for select using (true);
drop policy if exists "public all pools write" on bake_pools;
drop policy if exists "public pool update" on bake_pools;
drop policy if exists "staff insert pools" on bake_pools;
drop policy if exists "staff update pools" on bake_pools;
drop policy if exists "admin delete pools" on bake_pools;
create policy "staff insert pools" on bake_pools for insert to authenticated
  with check (public.has_staff_role(array['admin']));
create policy "staff update pools" on bake_pools for update to authenticated
  using (public.has_staff_role(array['admin', 'baker']))
  with check (public.has_staff_role(array['admin', 'baker']));
create policy "admin delete pools" on bake_pools for delete to authenticated
  using (public.has_staff_role(array['admin']));

drop policy if exists "public read orders" on orders;
drop policy if exists "public insert orders" on orders;
drop policy if exists "public update orders" on orders;
create policy "public insert orders" on orders for insert to anon, authenticated
  with check (status = 'pending' and total_cents >= 0);
drop policy if exists "staff read orders" on orders;
drop policy if exists "staff update orders" on orders;
drop policy if exists "admin delete orders" on orders;
create policy "staff read orders" on orders for select to authenticated
  using (public.has_staff_role(array['admin', 'baker']));
create policy "staff update orders" on orders for update to authenticated
  using (public.has_staff_role(array['admin', 'baker']))
  with check (public.has_staff_role(array['admin', 'baker']));
create policy "admin delete orders" on orders for delete to authenticated
  using (public.has_staff_role(array['admin']));

drop policy if exists "public read items" on order_items;
drop policy if exists "public insert items" on order_items;
create policy "staff read items" on order_items for select to authenticated
  using (public.has_staff_role(array['admin', 'baker']));
create policy "public insert items" on order_items for insert to anon, authenticated
  with check (qty > 0 and unit_price_cents >= 0);

drop policy if exists "public read participants" on pool_participants;
drop policy if exists "staff read participants" on pool_participants;
drop policy if exists "public insert participants" on pool_participants;
create policy "staff read participants" on pool_participants for select to authenticated
  using (public.has_staff_role(array['admin', 'baker']));

create or replace function public.join_bake_pool(
  p_pool_id uuid,
  p_customer_name text,
  p_qty int,
  p_order_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_pool public.bake_pools%rowtype;
begin
  if p_qty is null or p_qty < 1 or length(trim(p_customer_name)) < 2 then
    raise exception 'A customer name and positive quantity are required.';
  end if;

  update public.bake_pools
  set joined_qty = joined_qty + p_qty,
      status = case when joined_qty + p_qty >= target_qty then 'locked' else 'filling' end
  where id = p_pool_id and status = 'filling'
  returning * into updated_pool;

  if not found then
    raise exception 'This bake pool is unavailable.';
  end if;

  insert into public.pool_participants(pool_id, customer_name, qty, order_id)
  values (p_pool_id, trim(p_customer_name), p_qty, p_order_id);
end;
$$;

revoke all on function public.join_bake_pool(uuid, text, int, uuid) from public;
grant execute on function public.join_bake_pool(uuid, text, int, uuid) to anon, authenticated;

create or replace function public.track_orders(p_customer_name text, p_order_id text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(to_jsonb(matches) order by matches.created_at desc), '[]'::jsonb)
  from (
    select o.id, o.customer_name, o.kind, o.status, o.total_cents, o.created_at,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'product_name', i.product_name, 'qty', i.qty
        ) order by i.id)
        from public.order_items i where i.order_id = o.id
      ), '[]'::jsonb) as items
    from public.orders o
    where length(trim(coalesce(p_customer_name, ''))) >= 2
      and length(trim(coalesce(p_order_id, ''))) >= 8
      and o.id::text like lower(trim(p_order_id)) || '%'
      and lower(o.customer_name) = lower(trim(p_customer_name))
    order by o.created_at desc
    limit 20
  ) as matches;
$$;

revoke all on function public.track_orders(text, text) from public;
grant execute on function public.track_orders(text, text) to anon, authenticated;
