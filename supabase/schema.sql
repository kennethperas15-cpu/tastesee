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
  using (public.has_staff_role(array['admin']))
  with check (public.has_staff_role(array['admin']));
create policy "admin delete pools" on bake_pools for delete to authenticated
  using (public.has_staff_role(array['admin']));

drop policy if exists "public read orders" on orders;
drop policy if exists "public insert orders" on orders;
drop policy if exists "public update orders" on orders;
revoke insert on public.orders from anon, authenticated;
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

create or replace function public.guard_staff_order_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.has_staff_role(array['admin']) then
    return new;
  end if;

  if not public.has_staff_role(array['baker'])
    or (to_jsonb(new) - 'status') is distinct from (to_jsonb(old) - 'status')
    or not (
      (old.status = 'pending' and new.status = 'baking')
      or (old.status = 'baking' and new.status = 'ready')
    ) then
    raise exception 'Baker accounts can only advance orders from pending to baking to ready.';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_staff_order_update on public.orders;
create trigger guard_staff_order_update
before update on public.orders
for each row execute function public.guard_staff_order_update();

drop policy if exists "public read items" on order_items;
drop policy if exists "public insert items" on order_items;
create policy "staff read items" on order_items for select to authenticated
  using (public.has_staff_role(array['admin', 'baker']));
revoke insert on public.order_items from anon, authenticated;

drop policy if exists "public read participants" on pool_participants;
drop policy if exists "staff read participants" on pool_participants;
drop policy if exists "public insert participants" on pool_participants;
create policy "staff read participants" on pool_participants for select to authenticated
  using (public.has_staff_role(array['admin', 'baker']));
revoke insert on public.pool_participants from anon, authenticated;

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
    and joined_qty + p_qty <= target_qty
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

create or replace function public.create_order(
  p_customer_name text,
  p_phone text,
  p_kind text,
  p_address text,
  p_subtotal_cents int,
  p_discount_cents int,
  p_total_cents int,
  p_pool_id uuid,
  p_estimated_ready_at timestamptz,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_order_id uuid;
  expected_subtotal int;
  delivery_cents int;
  base_price_cents int;
  expected_unit_cents int;
  size_name text;
  icing_name text;
  topping_name text;
  item jsonb;
begin
  if length(trim(coalesce(p_customer_name, ''))) < 2
    or p_kind not in ('pickup', 'delivery')
    or p_subtotal_cents < 0
    or p_discount_cents < 0
    or jsonb_typeof(p_items) <> 'array'
    or jsonb_array_length(p_items) = 0 then
    raise exception 'Order details are invalid.';
  end if;

  if p_kind = 'delivery' and length(trim(coalesce(p_address, ''))) < 5 then
    raise exception 'A delivery address is required.';
  end if;

  select coalesce(sum((value->>'unit_price_cents')::int * (value->>'qty')::int), 0)
  into expected_subtotal
  from jsonb_array_elements(p_items);

  if expected_subtotal <> p_subtotal_cents then
    raise exception 'Order subtotal does not match its items.';
  end if;

  if p_pool_id is not null then
    if p_discount_cents <> round(p_subtotal_cents * 0.15) then
      raise exception 'Bake Pool discount is invalid.';
    end if;
  elsif p_discount_cents <> 0 then
    raise exception 'A discount requires a Bake Pool.';
  end if;

  delivery_cents := case when p_kind = 'delivery' then 6000 else 0 end;
  if p_total_cents <> p_subtotal_cents - p_discount_cents + delivery_cents then
    raise exception 'Order total is invalid.';
  end if;

  insert into public.orders (
    customer_name, phone, kind, address, status, subtotal_cents,
    discount_cents, total_cents, pool_id, is_pool_order, estimated_ready_at
  ) values (
    trim(p_customer_name), coalesce(p_phone, ''), p_kind, coalesce(p_address, ''),
    'pending', p_subtotal_cents, p_discount_cents, p_total_cents,
    p_pool_id, p_pool_id is not null, p_estimated_ready_at
  ) returning id into new_order_id;

  for item in select value from jsonb_array_elements(p_items) loop
    if length(trim(coalesce(item->>'name', ''))) = 0
      or coalesce((item->>'qty')::int, 0) < 1
      or coalesce((item->>'unit_price_cents')::int, -1) < 0 then
      raise exception 'An order item is invalid.';
    end if;

    select price_cents into base_price_cents
    from public.products
    where is_active and name = split_part(item->>'name', ' (', 1)
    limit 1;

    size_name := item->'custom'->>'size';
    icing_name := item->'custom'->>'icing';
    topping_name := item->'custom'->>'topping';
    if base_price_cents is null
      or coalesce(size_name, '') not in ('Regular', 'Large (+₱30)', 'Mini Box x4')
      or coalesce(icing_name, '') not in ('Classic glaze', 'Cream cheese', 'No icing', 'Extra cream (+₱15)')
      or coalesce(topping_name, '') not in ('None', 'Crushed Oreo (+₱15)', 'Biscoff crumble (+₱15)', 'Cocoa dust (free)') then
      raise exception 'An order item is not on the current menu.';
    end if;

    if size_name = 'Mini Box x4' then
      expected_unit_cents := round(base_price_cents * 3.4);
    else
      expected_unit_cents := base_price_cents
        + case when size_name = 'Large (+₱30)' then 3000 else 0 end
        + case when icing_name = 'Extra cream (+₱15)' then 1500 else 0 end
        + case when topping_name in ('Crushed Oreo (+₱15)', 'Biscoff crumble (+₱15)') then 1500 else 0 end;
    end if;

    if (item->>'unit_price_cents')::int <> expected_unit_cents then
      raise exception 'An order item price does not match the current menu.';
    end if;

    insert into public.order_items (
      order_id, product_name, qty, unit_price_cents, customizations
    ) values (
      new_order_id, item->>'name', (item->>'qty')::int,
      (item->>'unit_price_cents')::int, coalesce(item->'custom', '{}'::jsonb)
    );
  end loop;

  if p_pool_id is not null then
    perform public.join_bake_pool(
      p_pool_id, p_customer_name,
      (select sum((value->>'qty')::int)::int from jsonb_array_elements(p_items)),
      new_order_id
    );
  end if;

  return new_order_id;
end;
$$;

revoke all on function public.create_order(text, text, text, text, int, int, int, uuid, timestamptz, jsonb) from public;
grant execute on function public.create_order(text, text, text, text, int, int, int, uuid, timestamptz, jsonb) to anon, authenticated;

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
      and trim(coalesce(p_order_id, '')) ~ '^[0-9a-fA-F]{8}$'
      and left(o.id::text, 8) = lower(trim(p_order_id))
      and lower(o.customer_name) = lower(trim(p_customer_name))
    order by o.created_at desc
    limit 20
  ) as matches;
$$;

revoke all on function public.track_orders(text, text) from public;
grant execute on function public.track_orders(text, text) to anon, authenticated;
