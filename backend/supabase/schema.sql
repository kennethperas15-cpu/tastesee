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

alter table public.orders add column if not exists delivery_lat double precision;
alter table public.orders add column if not exists delivery_lng double precision;
alter table public.orders add column if not exists delivery_distance_meters int not null default 0;
alter table public.orders add column if not exists delivery_fee_cents int not null default 0;
alter table public.orders add column if not exists driver_id uuid references auth.users(id) on delete set null;
alter table public.orders add column if not exists driver_lat double precision;
alter table public.orders add column if not exists driver_lng double precision;
alter table public.orders add column if not exists customer_id uuid references auth.users(id) on delete set null;
create index if not exists orders_customer_id_idx on public.orders (customer_id);

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

alter table public.staff_access drop constraint if exists staff_access_role_check;
alter table public.staff_access add constraint staff_access_role_check
  check (role in ('admin', 'baker', 'driver'));

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

create or replace function public.list_staff_access()
returns table(user_id uuid, email text, role text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_staff_role(array['admin']) then
    raise exception 'Only an admin can view staff accounts.';
  end if;

  return query
  select sa.user_id, au.email::text, sa.role
  from public.staff_access sa
  join auth.users au on au.id = sa.user_id
  order by sa.role, lower(au.email);
end;
$$;

create or replace function public.set_staff_access(p_email text, p_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_user_id uuid;
  current_role text;
begin
  if not public.has_staff_role(array['admin']) then
    raise exception 'Only an admin can manage staff accounts.';
  end if;

  if p_role is null or p_role not in ('admin', 'baker', 'driver')
    or length(trim(coalesce(p_email, ''))) < 3 then
    raise exception 'Enter a valid email and select admin, baker, or driver.';
  end if;

  select id into target_user_id
  from auth.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  if target_user_id is null then
    raise exception 'That user must sign in with Google once before an admin can assign a staff role.';
  end if;

  if target_user_id = (select auth.uid()) then
    raise exception 'Admins cannot change their own staff role.';
  end if;

  perform pg_advisory_xact_lock(hashtext('public.staff_access_admins'));
  select role into current_role from public.staff_access where user_id = target_user_id;
  if current_role = 'admin' and p_role <> 'admin'
    and (select count(*) from public.staff_access where role = 'admin') <= 1 then
    raise exception 'The last admin account cannot be downgraded.';
  end if;

  insert into public.staff_access(user_id, role)
  values (target_user_id, p_role)
  on conflict (user_id) do update set role = excluded.role;
end;
$$;

create or replace function public.remove_staff_access(p_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_user_id uuid;
  current_role text;
begin
  if not public.has_staff_role(array['admin']) then
    raise exception 'Only an admin can manage staff accounts.';
  end if;

  select id into target_user_id
  from auth.users
  where lower(email) = lower(trim(coalesce(p_email, '')))
  limit 1;
  if target_user_id is null then
    raise exception 'No Google account was found for that email.';
  end if;
  if target_user_id = (select auth.uid()) then
    raise exception 'Admins cannot revoke their own staff role.';
  end if;

  perform pg_advisory_xact_lock(hashtext('public.staff_access_admins'));
  select role into current_role from public.staff_access where user_id = target_user_id;
  if current_role is null then
    raise exception 'That account does not currently have staff access.';
  end if;
  if current_role = 'admin'
    and (select count(*) from public.staff_access where role = 'admin') <= 1 then
    raise exception 'The last admin account cannot be removed.';
  end if;

  delete from public.staff_access where user_id = target_user_id;
end;
$$;

revoke all on function public.list_staff_access() from public, anon;
revoke all on function public.set_staff_access(text, text) from public, anon;
revoke all on function public.remove_staff_access(text) from public, anon;
grant execute on function public.list_staff_access() to authenticated;
grant execute on function public.set_staff_access(text, text) to authenticated;
grant execute on function public.remove_staff_access(text) to authenticated;

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
  using (
    public.has_staff_role(array['admin', 'baker'])
    or (
      public.has_staff_role(array['driver'])
      and kind = 'delivery'
      and (status = 'ready' or (driver_id = (select auth.uid()) and status = 'out_for_delivery'))
    )
  );
create policy "staff update orders" on orders for update to authenticated
  using (
    public.has_staff_role(array['admin', 'baker'])
    or (
      public.has_staff_role(array['driver'])
      and kind = 'delivery'
      and (status = 'ready' or (driver_id = (select auth.uid()) and status = 'out_for_delivery'))
    )
  )
  with check (
    public.has_staff_role(array['admin', 'baker'])
    or (
      public.has_staff_role(array['driver'])
      and kind = 'delivery'
      and driver_id = (select auth.uid())
      and status in ('out_for_delivery', 'completed')
    )
  );
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

  if public.has_staff_role(array['baker']) then
    if (to_jsonb(new) - 'status') is distinct from (to_jsonb(old) - 'status')
      or not (
        (old.status = 'pending' and new.status = 'baking')
        or (old.status = 'baking' and new.status = 'ready')
      ) then
      raise exception 'Baker accounts can only advance orders from pending to baking to ready.';
    end if;
    return new;
  end if;

  if not public.has_staff_role(array['driver']) then
    raise exception 'A staff role is required to update an order.';
  end if;

  if old.kind <> 'delivery' then
    raise exception 'Riders can only update delivery orders.';
  elsif old.status = 'ready' and old.driver_id is null
    and new.status = 'out_for_delivery' and new.driver_id = (select auth.uid())
    and (to_jsonb(new) - array['status', 'driver_id']) is not distinct from
      (to_jsonb(old) - array['status', 'driver_id']) then
    return new;
  elsif old.status = 'out_for_delivery' and old.driver_id = (select auth.uid())
    and new.status = old.status and new.driver_id = old.driver_id
    and (to_jsonb(new) - array['driver_lat', 'driver_lng']) is not distinct from
      (to_jsonb(old) - array['driver_lat', 'driver_lng']) then
    return new;
  elsif old.status = 'out_for_delivery' and old.driver_id = (select auth.uid())
    and new.status = 'completed' and new.driver_id = old.driver_id
    and (to_jsonb(new) - 'status') is not distinct from (to_jsonb(old) - 'status') then
    return new;
  end if;

  raise exception 'Riders can only accept ready deliveries, update their active location, or mark their delivery completed.';
end;
$$;

drop trigger if exists guard_staff_order_update on public.orders;
create trigger guard_staff_order_update
before update on public.orders
for each row execute function public.guard_staff_order_update();

drop policy if exists "public read items" on order_items;
drop policy if exists "public insert items" on order_items;
drop policy if exists "staff read items" on order_items;
create policy "staff read items" on order_items for select to authenticated
  using (
    public.has_staff_role(array['admin', 'baker'])
    or (
      public.has_staff_role(array['driver'])
      and exists (
        select 1 from public.orders o
        where o.id = order_items.order_id
          and o.kind = 'delivery'
          and (o.status = 'ready' or (o.driver_id = (select auth.uid()) and o.status = 'out_for_delivery'))
      )
    )
  );
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

drop function if exists public.create_order(text, text, text, text, int, int, int, uuid, timestamptz, jsonb);

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
  p_items jsonb,
  p_delivery_lat double precision default null,
  p_delivery_lng double precision default null,
  p_delivery_distance_meters int default 0,
  p_delivery_fee_cents int default 0
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_order_id uuid;
  expected_subtotal int;
  order_bun_count int;
  base_price_cents int;
  expected_unit_cents int;
  item jsonb;
begin
  if (select auth.uid()) is null
    or public.has_staff_role(array['admin', 'baker', 'driver']) then
    raise exception 'A signed-in customer account is required to place an order.';
  end if;

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

  if p_kind = 'delivery' then
    if p_delivery_lat is null or p_delivery_lng is null
      or p_delivery_lat not between 10.25 and 10.39
      or p_delivery_lng not between 123.78 and 123.96
      or p_delivery_distance_meters is null or p_delivery_distance_meters < 0
      or p_delivery_fee_cents is null
      or p_delivery_fee_cents <> 4000 + round(p_delivery_distance_meters * 1.2)::int then
      raise exception 'Delivery coordinates, distance, or fee are invalid.';
    end if;
  elsif p_delivery_lat is not null or p_delivery_lng is not null
    or p_delivery_distance_meters <> 0 or p_delivery_fee_cents <> 0 then
    raise exception 'Pickup orders cannot include delivery details.';
  end if;

  select coalesce(sum((value->>'unit_price_cents')::int * (value->>'qty')::int), 0)
  into expected_subtotal
  from jsonb_array_elements(p_items);

  if expected_subtotal <> p_subtotal_cents then
    raise exception 'Order subtotal does not match its items.';
  end if;

  select coalesce(sum((value->>'qty')::int), 0)
  into order_bun_count
  from jsonb_array_elements(p_items);

  if order_bun_count < 1 or order_bun_count > 4 then
    raise exception 'A bun box must contain between one and four buns.';
  end if;

  if p_pool_id is not null then
    if p_discount_cents <> round(p_subtotal_cents * 0.15) then
      raise exception 'Bake Pool discount is invalid.';
    end if;
  elsif p_discount_cents <> (case when order_bun_count = 4 then 1000 else 0 end) then
    raise exception 'Four-bun box discount is invalid.';
  end if;

  if p_total_cents <> p_subtotal_cents - p_discount_cents + p_delivery_fee_cents then
    raise exception 'Order total is invalid.';
  end if;

  insert into public.orders (
    customer_name, phone, kind, address, status, subtotal_cents,
    discount_cents, total_cents, pool_id, is_pool_order, estimated_ready_at,
    delivery_lat, delivery_lng, delivery_distance_meters, delivery_fee_cents, customer_id
  ) values (
    trim(p_customer_name), coalesce(p_phone, ''), p_kind, coalesce(p_address, ''),
    'pending', p_subtotal_cents, p_discount_cents, p_total_cents,
    p_pool_id, p_pool_id is not null, p_estimated_ready_at,
    p_delivery_lat, p_delivery_lng, p_delivery_distance_meters, p_delivery_fee_cents, auth.uid()
  ) returning id into new_order_id;

  for item in select value from jsonb_array_elements(p_items) loop
    if length(trim(coalesce(item->>'name', ''))) = 0
      or coalesce((item->>'qty')::int, 0) < 1
      or coalesce((item->>'unit_price_cents')::int, -1) < 0 then
      raise exception 'An order item is invalid.';
    end if;

    select price_cents into base_price_cents
    from public.products
    where is_active and name = item->>'name'
    limit 1;

    if base_price_cents is null
      or coalesce((item->>'qty')::int, 0) < 1
      or coalesce((item->>'qty')::int, 0) > 4 then
      raise exception 'An order item is not on the current menu.';
    end if;

    expected_unit_cents := base_price_cents;

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

revoke all on function public.create_order(text, text, text, text, int, int, int, uuid, timestamptz, jsonb, double precision, double precision, int, int) from public;
grant execute on function public.create_order(text, text, text, text, int, int, int, uuid, timestamptz, jsonb, double precision, double precision, int, int) to authenticated;

create or replace function public.track_orders(p_customer_name text, p_order_id text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(to_jsonb(matches) order by matches.created_at desc), '[]'::jsonb)
  from (
    select o.id, o.customer_name, o.kind, o.address, o.status, o.total_cents, o.created_at,
      o.delivery_lat, o.delivery_lng, o.delivery_distance_meters, o.delivery_fee_cents,
      o.driver_lat, o.driver_lng,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'product_name', i.product_name, 'qty', i.qty
        ) order by i.id)
        from public.order_items i where i.order_id = o.id
      ), '[]'::jsonb) as items
    from public.orders o
    where length(trim(coalesce(p_customer_name, ''))) >= 2
      and (select auth.uid()) is not null
      and trim(coalesce(p_order_id, '')) ~ '^[0-9a-fA-F]{8}$'
      and left(o.id::text, 8) = lower(trim(p_order_id))
      and lower(o.customer_name) = lower(trim(p_customer_name))
      and o.customer_id = (select auth.uid())
    order by o.created_at desc
    limit 20
  ) as matches;
$$;

revoke all on function public.track_orders(text, text) from public;
grant execute on function public.track_orders(text, text) to authenticated;

-- CUSTOMER COMMUNITY MOMENTS
create table if not exists public.community_moments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  caption text not null default '' check (char_length(caption) <= 160),
  location_tag text not null default '' check (char_length(location_tag) <= 80),
  image_path text not null check (image_path like user_id::text || '/%'),
  created_at timestamptz not null default now()
);

create index if not exists community_moments_created_at_idx
  on public.community_moments (created_at desc);
create index if not exists community_moments_user_id_idx
  on public.community_moments (user_id);

alter table public.community_moments enable row level security;
revoke all on public.community_moments from anon, authenticated;
grant select on public.community_moments to anon, authenticated;
grant insert, delete on public.community_moments to authenticated;

drop policy if exists "Public can view community moments" on public.community_moments;
create policy "Public can view community moments" on public.community_moments
  for select to anon, authenticated using (true);
drop policy if exists "Customers can publish community moments" on public.community_moments;
create policy "Customers can publish community moments" on public.community_moments
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and not (select public.has_staff_role(array['admin', 'baker', 'driver']))
  );
drop policy if exists "Customers can delete own community moments" on public.community_moments;
create policy "Customers can delete own community moments" on public.community_moments
  for delete to authenticated
  using (
    user_id = (select auth.uid())
    and not (select public.has_staff_role(array['admin', 'baker', 'driver']))
  );

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('community-moments', 'community-moments', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Customers upload own community moment photos" on storage.objects;
create policy "Customers upload own community moment photos" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'community-moments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and not (select public.has_staff_role(array['admin', 'baker', 'driver']))
  );
drop policy if exists "Customers delete own community moment photos" on storage.objects;
create policy "Customers delete own community moment photos" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'community-moments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and not (select public.has_staff_role(array['admin', 'baker', 'driver']))
  );
grant insert, delete on storage.objects to authenticated;

-- BAKER STOCK BOARD + KITCHEN NOTICES
-- Bakers see live stock, adjust daily availability, and message the admin
-- (for example: stop restocking a flavour). All writes go through RPCs so
-- bakers can never touch prices, orders, or other staff rows.
create table if not exists public.stock_notices (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  kind text not null check (kind in ('stop_restock', 'low_stock', 'note')),
  message text not null check (char_length(message) between 3 and 280),
  is_resolved boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists stock_notices_created_at_idx
  on public.stock_notices (created_at desc);

alter table public.stock_notices enable row level security;
revoke all on public.stock_notices from anon, authenticated;

create or replace function public.update_product_stock(
  p_product_id uuid,
  p_stock_daily int,
  p_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_staff_role(array['admin', 'baker']) then
    raise exception 'Only bakers or admins can update stock.';
  end if;

  if p_stock_daily is null or p_stock_daily < 0 or p_stock_daily > 500 then
    raise exception 'Daily stock must be between 0 and 500.';
  end if;

  update public.products
  set stock_daily = p_stock_daily,
      is_active = coalesce(p_is_active, is_active)
  where id = p_product_id;

  if not found then
    raise exception 'That product was not found.';
  end if;
end;
$$;

create or replace function public.create_stock_notice(
  p_product_id uuid,
  p_kind text,
  p_message text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_message text := trim(coalesce(p_message, ''));
begin
  if not public.has_staff_role(array['admin', 'baker']) then
    raise exception 'Only bakers or admins can message the kitchen board.';
  end if;

  if p_kind is null or p_kind not in ('stop_restock', 'low_stock', 'note')
    or char_length(clean_message) < 3 or char_length(clean_message) > 280 then
    raise exception 'Choose a notice type and write 3–280 characters.';
  end if;

  if p_product_id is not null
    and not exists (select 1 from public.products where id = p_product_id) then
    raise exception 'That product was not found.';
  end if;

  insert into public.stock_notices (created_by, product_id, kind, message)
  values ((select auth.uid()), p_product_id, p_kind, clean_message);
end;
$$;

create or replace function public.list_stock_notices()
returns table(
  id uuid,
  product_name text,
  author_email text,
  kind text,
  message text,
  is_resolved boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_staff_role(array['admin', 'baker']) then
    raise exception 'Only bakers or admins can read kitchen notices.';
  end if;

  return query
  select n.id, p.name, au.email::text, n.kind, n.message, n.is_resolved, n.created_at
  from public.stock_notices n
  left join public.products p on p.id = n.product_id
  join auth.users au on au.id = n.created_by
  where public.has_staff_role(array['admin']) or n.created_by = (select auth.uid())
  order by n.is_resolved, n.created_at desc;
end;
$$;

create or replace function public.resolve_stock_notice(p_notice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_staff_role(array['admin']) then
    raise exception 'Only an admin can resolve kitchen notices.';
  end if;

  update public.stock_notices
  set is_resolved = true
  where id = p_notice_id and is_resolved = false;

  if not found then
    raise exception 'That notice was not found or is already resolved.';
  end if;
end;
$$;

revoke all on function public.update_product_stock(uuid, int, boolean) from public, anon;
revoke all on function public.create_stock_notice(uuid, text, text) from public, anon;
revoke all on function public.list_stock_notices() from public, anon;
revoke all on function public.resolve_stock_notice(uuid) from public, anon;
grant execute on function public.update_product_stock(uuid, int, boolean) to authenticated;
grant execute on function public.create_stock_notice(uuid, text, text) to authenticated;
grant execute on function public.list_stock_notices() to authenticated;
grant execute on function public.resolve_stock_notice(uuid) to authenticated;
