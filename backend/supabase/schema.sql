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

-- STORE SETTINGS: one row of operational limits.
-- Slot capacity is the number of bun boxes the kitchen will accept per day.
-- It may never drop below 60, no matter who is signed in.
create table if not exists public.store_settings (
  id boolean primary key default true check (id),
  slot_capacity int not null default 80 check (slot_capacity >= 60),
  delivery_notice text not null default '' check (char_length(delivery_notice) <= 240),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.store_settings
  add column if not exists delivery_notice text not null default '';

insert into public.store_settings (id) values (true)
on conflict (id) do nothing;

alter table public.store_settings enable row level security;
revoke all on public.store_settings from anon, authenticated;

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

-- ORDERING LIMITS + FRAUD PREVENTION
-- box_count is the number of 4-bun boxes in the transaction (1–10).
-- order_day is the Asia/Manila calendar day used by the duplicate guard.
alter table public.orders add column if not exists box_count int not null default 1;
alter table public.orders add column if not exists device_key text;
alter table public.orders add column if not exists device_model text;
alter table public.orders add column if not exists location_key text;
alter table public.orders add column if not exists location_source text;
alter table public.orders add column if not exists client_ip text;
alter table public.orders add column if not exists order_day date not null default ((now() at time zone 'Asia/Manila')::date);

-- Migrations run from the SQL editor without a staff JWT, so the order-update
-- guard trigger would reject the backfills below. It is recreated afterwards.
drop trigger if exists guard_staff_order_update on public.orders;

-- Existing orders must keep their real day instead of the migration date.
update public.orders
set order_day = (created_at at time zone 'Asia/Manila')::date
where order_day <> (created_at at time zone 'Asia/Manila')::date;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'orders_box_count_range'
  ) then
    alter table public.orders
      add constraint orders_box_count_range check (box_count between 1 and 10);
  end if;
end;
$$;

-- Backfill legacy orders from their item quantities once.
-- (Runs after order_items is created, see below.)

-- Hard database guard: one order per device + location per day.
-- (The older non-unique duplicate index is retired to avoid a redundant index.)
drop index if exists public.orders_duplicate_guard_idx;
create unique index if not exists orders_device_location_day_unique
  on public.orders (device_key, location_key, order_day)
  where status <> 'cancelled' and device_key is not null and location_key is not null;

-- ORDER ITEMS
create table if not exists order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  product_name text not null,
  qty int not null check (qty between 1 and 40),
  unit_price_cents int not null,
  customizations jsonb default '{}'
);

-- Backfill legacy orders from their item quantities once.
-- Legacy buns were counted one per box; the new model packs 4 buns per box.
update public.orders o
set box_count = least(10, greatest(1, ceil((
  select coalesce(sum(i.qty), 1)::numeric from public.order_items i where i.order_id = o.id
) / 4.0)::int))
where o.box_count = 1
  and exists (
    select 1 from public.order_items i
    where i.order_id = o.id
    group by i.order_id
    having sum(i.qty) <> 1
  );

-- One line can hold up to 40 buns (10 boxes x 4 buns).
alter table public.order_items drop constraint if exists order_items_qty_check;
alter table public.order_items add constraint order_items_qty_check check (qty between 1 and 40);

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
  role text not null check (role in ('admin', 'baker', 'driver', 'owner')),
  created_at timestamptz not null default now()
);

alter table public.staff_access drop constraint if exists staff_access_role_check;
alter table public.staff_access add constraint staff_access_role_check
  check (role in ('admin', 'baker', 'driver', 'owner'));

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
    where user_id = auth.uid()
      and (role = any(p_roles) or (role = 'owner' and 'admin' = any(p_roles)))
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

  if p_role is null or p_role not in ('admin', 'owner', 'baker', 'driver')
    or length(trim(coalesce(p_email, ''))) < 3 then
    raise exception 'Enter a valid email and select owner, admin, baker, or driver.';
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
  if current_role in ('admin', 'owner') and p_role not in ('admin', 'owner')
    and (select count(*) from public.staff_access where role in ('admin', 'owner')) <= 1 then
    raise exception 'The last admin or owner account cannot be downgraded.';
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
  if current_role in ('admin', 'owner')
    and (select count(*) from public.staff_access where role in ('admin', 'owner')) <= 1 then
    raise exception 'The last admin or owner account cannot be removed.';
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

-- SLOT CAPACITY: the daily box limit.
-- The remaining daily slot counts are private to admin/owner accounts. The
-- customer-facing storefront never sees them; it only gets the delivery notice.
create or replace function public.get_slot_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if not public.has_staff_role(array['admin', 'owner']) then
    raise exception 'Daily slot details are available to admin and owner accounts only.';
  end if;

  select jsonb_build_object(
    'capacity', s.slot_capacity,
    'min_capacity', 60,
    'used_today', coalesce(used.boxes, 0),
    'remaining', greatest(0, s.slot_capacity - coalesce(used.boxes, 0)),
    'delivery_notice', coalesce(s.delivery_notice, '')
  )
  into result
  from public.store_settings s
  left join (
    select sum(o.box_count)::int as boxes
    from public.orders o
    where o.status <> 'cancelled'
      and o.order_day = (now() at time zone 'Asia/Manila')::date
  ) used on true
  limit 1;

  return result;
end;
$$;

-- The delivery notice is customer-facing, but carries no slot numbers.
create or replace function public.get_delivery_notice()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select delivery_notice from public.store_settings order by id limit 1), '');
$$;

create or replace function public.update_slot_capacity(p_capacity int)
returns int
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_staff_role(array['admin', 'owner']) then
    raise exception 'Only an admin or owner can change the daily slot capacity.';
  end if;

  if p_capacity is null or p_capacity < 60 or p_capacity > 1000 then
    raise exception 'Slot capacity must be between 60 and 1000 boxes per day.';
  end if;

  insert into public.store_settings (id, slot_capacity, updated_by, updated_at)
  values (true, p_capacity, (select auth.uid()), now())
  on conflict (id) do update
    set slot_capacity = excluded.slot_capacity,
        updated_by = excluded.updated_by,
        updated_at = now();

  return p_capacity;
end;
$$;

revoke all on function public.get_slot_status() from public, anon;
revoke all on function public.get_delivery_notice() from public;
revoke all on function public.update_slot_capacity(int) from public, anon;
grant execute on function public.get_slot_status() to authenticated;
grant execute on function public.get_delivery_notice() to anon, authenticated;
grant execute on function public.update_slot_capacity(int) to authenticated;

create or replace function public.update_delivery_notice(p_notice text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_notice text := trim(coalesce(p_notice, ''));
begin
  if not public.has_staff_role(array['admin', 'owner']) then
    raise exception 'Only an admin or owner can change the delivery notice.';
  end if;

  if char_length(clean_notice) > 240 then
    raise exception 'The delivery notice must be 240 characters or fewer.';
  end if;

  update public.store_settings
  set delivery_notice = clean_notice,
      updated_by = (select auth.uid()),
      updated_at = now()
  where id;

  return clean_notice;
end;
$$;

revoke all on function public.update_delivery_notice(text) from public, anon;
grant execute on function public.update_delivery_notice(text) to authenticated;

-- CHECKOUT GATEWAY (preflight "middleware" for the browser).
-- This is read-only and returns a structured decision. create_order still
-- repeats every check atomically before saving, so the gateway can never be
-- bypassed by calling the RPC directly.
create or replace function public.check_order_gateway(
  p_box_count int,
  p_device_key text default null,
  p_location_key text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  today date := (now() at time zone 'Asia/Manila')::date;
  slots_capacity int;
  slots_used int;
  clean_location text := nullif(trim(coalesce(p_location_key, '')), '');
  device_hash text;
begin
  if p_box_count is null or p_box_count < 1 or p_box_count > 10 then
    return jsonb_build_object(
      'allowed', false,
      'code', 'order_limit',
      'message', 'Order Limit Reached: You can only purchase a maximum of 10 boxes per order.'
    );
  end if;

  select slot_capacity into slots_capacity from public.store_settings order by id limit 1;
  select coalesce(sum(box_count), 0) into slots_used
  from public.orders
  where status <> 'cancelled' and order_day = today;

  if slots_capacity is null then
    return jsonb_build_object('allowed', false, 'code', 'unavailable', 'message', 'The kitchen is not accepting orders right now.');
  end if;

  if slots_used + p_box_count > slots_capacity then
    return jsonb_build_object(
      'allowed', false,
      'code', 'slots_full',
      'message', 'Today''s order slots are full. Please try again tomorrow.'
    );
  end if;

  if p_device_key is not null and length(trim(p_device_key)) > 0 and clean_location is not null then
    device_hash := md5(trim(p_device_key));
    if exists (
      select 1 from public.orders o
      where o.device_key = device_hash
        and o.location_key = clean_location
        and o.order_day = today
        and o.status <> 'cancelled'
    ) then
      return jsonb_build_object(
        'allowed', false,
        'code', 'duplicate',
        'message', 'Duplicate order blocked: an order from this same location and device was already placed today.'
      );
    end if;
  end if;

  return jsonb_build_object('allowed', true, 'code', 'ok');
end;
$$;

revoke all on function public.check_order_gateway(int, text, text) from public, anon;
grant execute on function public.check_order_gateway(int, text, text) to authenticated;

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
drop function if exists public.create_order(text, text, text, text, int, int, int, uuid, timestamptz, jsonb, double precision, double precision, int, int);

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
  p_delivery_fee_cents int default 0,
  p_box_count int default 1,
  p_device_key text default null,
  p_device_model text default null,
  p_location_key text default null,
  p_location_source text default null,
  p_client_ip text default null
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
  today date := (now() at time zone 'Asia/Manila')::date;
  slots_capacity int;
  slots_used int;
  device_hash text;
  clean_location text := nullif(trim(coalesce(p_location_key, '')), '');
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

  -- Delivery is not fulfilled in-house: the customer books Grab/Lalamove/Maxim
  -- and pays that rider directly, so the store never charges a delivery fee.
  if p_kind = 'delivery' then
    if p_delivery_fee_cents is null or p_delivery_fee_cents <> 0
      or coalesce(p_delivery_distance_meters, 0) <> 0 then
      raise exception 'Delivery is handled by your own rider booking, so no delivery fee is charged by the store.';
    end if;
    if (p_delivery_lat is not null or p_delivery_lng is not null)
      and (p_delivery_lat is null or p_delivery_lng is null
        or p_delivery_lat not between 10.25 and 10.39
        or p_delivery_lng not between 123.78 and 123.96) then
      raise exception 'Delivery coordinates are invalid.';
    end if;
  elsif p_delivery_lat is not null or p_delivery_lng is not null
    or coalesce(p_delivery_distance_meters, 0) <> 0 or coalesce(p_delivery_fee_cents, 0) <> 0 then
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

  -- A transaction carries between 1 and 10 boxes, never more.
  if p_box_count is null or p_box_count < 1 or p_box_count > 10 then
    raise exception 'Order Limit Reached: You can only purchase a maximum of 10 boxes per order.';
  end if;

  -- Every box is a fixed 4-bun box.
  if order_bun_count <> p_box_count * 4 then
    raise exception 'Each box must hold exactly 4 buns (received % buns for % boxes).', order_bun_count, p_box_count;
  end if;

  if p_pool_id is not null then
    if p_discount_cents <> round(p_subtotal_cents * 0.15) then
      raise exception 'Bake Pool discount is invalid.';
    end if;
  elsif p_discount_cents <> ((order_bun_count / 4) * 1000) then
    raise exception 'Four-bun box discount is invalid.';
  end if;

  if p_total_cents <> p_subtotal_cents - p_discount_cents + coalesce(p_delivery_fee_cents, 0) then
    raise exception 'Order total is invalid.';
  end if;

  -- Serialize slot checks for the day so two customers cannot book the
  -- same last slot at the same moment.
  perform pg_advisory_xact_lock(hashtext('taste_see_slots_' || today::text));

  select slot_capacity into slots_capacity from public.store_settings order by id limit 1;
  if slots_capacity is null then
    raise exception 'The kitchen is not accepting orders right now.';
  end if;

  select coalesce(sum(box_count), 0) into slots_used
  from public.orders
  where status <> 'cancelled' and order_day = today;

  if slots_used + p_box_count > slots_capacity then
    raise exception 'Today''s order slots are full. Please try again tomorrow.';
  end if;

  -- Duplicate guard: same location AND same device/unit already ordered today.
  if p_device_key is not null and length(trim(p_device_key)) > 0 and clean_location is not null then
    device_hash := md5(trim(p_device_key));
    if exists (
      select 1 from public.orders o
      where o.device_key = device_hash
        and o.location_key = clean_location
        and o.order_day = today
        and o.status <> 'cancelled'
    ) then
      raise exception 'Duplicate order blocked: an order from this same location and device was already placed today.';
    end if;
  else
    device_hash := null;
  end if;

  insert into public.orders (
    customer_name, phone, kind, address, status, subtotal_cents,
    discount_cents, total_cents, pool_id, is_pool_order, estimated_ready_at,
    delivery_lat, delivery_lng, delivery_distance_meters, delivery_fee_cents, customer_id,
    box_count, device_key, device_model, location_key, location_source, client_ip, order_day
  ) values (
    trim(p_customer_name), coalesce(p_phone, ''), p_kind, coalesce(p_address, ''),
    'pending', p_subtotal_cents, p_discount_cents, p_total_cents,
    p_pool_id, p_pool_id is not null, p_estimated_ready_at,
    p_delivery_lat, p_delivery_lng, coalesce(p_delivery_distance_meters, 0), coalesce(p_delivery_fee_cents, 0), auth.uid(),
    p_box_count, device_hash, nullif(trim(coalesce(p_device_model, '')), ''),
    clean_location, nullif(trim(coalesce(p_location_source, '')), ''),
    nullif(trim(coalesce(p_client_ip, '')), ''), today
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
      or coalesce((item->>'qty')::int, 0) > 40 then
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

revoke all on function public.create_order(text, text, text, text, int, int, int, uuid, timestamptz, jsonb, double precision, double precision, int, int, int, text, text, text, text, text) from public;
grant execute on function public.create_order(text, text, text, text, int, int, int, uuid, timestamptz, jsonb, double precision, double precision, int, int, int, text, text, text, text, text) to authenticated;

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
      o.box_count,
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

-- STAFF MESSAGING: two-way chat between bakers/riders and the admin.
-- Bakers and riders can only message the admin; the admin can reply to the
-- baker channel, the rider channel, or fellow admins. Each role only ever
-- sees its own channel plus messages it sent.
create table if not exists public.staff_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  target_role text not null check (target_role in ('admin', 'baker', 'driver')),
  body text not null check (char_length(body) between 1 and 500),
  order_id uuid references public.orders(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists staff_messages_created_at_idx
  on public.staff_messages (created_at desc);
create index if not exists staff_messages_target_role_idx
  on public.staff_messages (target_role);

alter table public.staff_messages enable row level security;
revoke all on public.staff_messages from anon, authenticated;

create or replace function public.send_staff_message(
  p_target_role text,
  p_body text,
  p_order_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  sender_role text;
  clean_body text := trim(coalesce(p_body, ''));
begin
  select role into sender_role
  from public.staff_access
  where user_id = (select auth.uid());

  if sender_role is null then
    raise exception 'Only staff accounts can send messages.';
  end if;

  if sender_role = 'owner' then
    sender_role := 'admin';
  end if;

  if p_target_role is null
    or p_target_role not in ('admin', 'baker', 'driver')
    or char_length(clean_body) < 1 or char_length(clean_body) > 500 then
    raise exception 'Choose who to message and write 1–500 characters.';
  end if;

  if sender_role <> 'admin' and p_target_role <> 'admin' then
    raise exception 'Bakers and riders can only message the admin.';
  end if;

  if p_order_id is not null
    and not exists (select 1 from public.orders where id = p_order_id) then
    raise exception 'That order was not found.';
  end if;

  insert into public.staff_messages (sender_id, target_role, body, order_id)
  values ((select auth.uid()), p_target_role, clean_body, p_order_id);
end;
$$;

create or replace function public.list_staff_messages()
returns table(
  id uuid,
  sender_email text,
  sender_role text,
  target_role text,
  body text,
  order_id uuid,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_role text;
begin
  select role into viewer_role
  from public.staff_access
  where user_id = (select auth.uid());

  if viewer_role is null then
    raise exception 'Only staff accounts can read messages.';
  end if;

  if viewer_role = 'owner' then
    viewer_role := 'admin';
  end if;

  return query
  select m.id, au.email::text, sa.role, m.target_role, m.body, m.order_id, m.created_at
  from public.staff_messages m
  join auth.users au on au.id = m.sender_id
  left join public.staff_access sa on sa.user_id = m.sender_id
  where viewer_role = 'admin'
    or m.target_role = viewer_role
    or m.sender_id = (select auth.uid())
  order by m.created_at desc
  limit 50;
end;
$$;

revoke all on function public.send_staff_message(text, text, uuid) from public, anon;
revoke all on function public.list_staff_messages() from public, anon;
grant execute on function public.send_staff_message(text, text, uuid) to authenticated;
grant execute on function public.list_staff_messages() to authenticated;

-- BAKER MENU MANAGEMENT: bakers can add flavours and remove them from sale.
-- Removing only deactivates (order history is preserved); only admins can
-- permanently delete a flavour.
create or replace function public.create_product(
  p_name text,
  p_description text,
  p_price_cents int,
  p_emoji text,
  p_category text,
  p_stock_daily int
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_name text := trim(coalesce(p_name, ''));
  new_id uuid;
begin
  if not public.has_staff_role(array['admin', 'baker']) then
    raise exception 'Only bakers or admins can add flavours.';
  end if;

  if char_length(clean_name) < 2 or char_length(clean_name) > 60 then
    raise exception 'Flavour name must be 2–60 characters.';
  end if;

  if exists (select 1 from public.products where lower(name) = lower(clean_name)) then
    raise exception 'That flavour already exists — reactivate it from the stock board instead.';
  end if;

  if p_price_cents is null or p_price_cents < 100 or p_price_cents > 100000 then
    raise exception 'Price must be between ₱1 and ₱1,000.';
  end if;

  if p_stock_daily is null or p_stock_daily < 0 or p_stock_daily > 500 then
    raise exception 'Daily stock must be between 0 and 500.';
  end if;

  insert into public.products (name, description, price_cents, emoji, category, stock_daily, is_active)
  values (
    clean_name,
    trim(coalesce(p_description, '')),
    p_price_cents,
    nullif(trim(coalesce(p_emoji, '')), ''),
    nullif(trim(coalesce(p_category, '')), ''),
    p_stock_daily,
    true
  )
  returning id into new_id;

  update public.products
  set emoji = '🥮', category = 'signature'
  where id = new_id and (emoji is null or category is null);

  return new_id;
end;
$$;

create or replace function public.delete_product(p_product_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_staff_role(array['admin']) then
    raise exception 'Only an admin can permanently delete a flavour. Bakers can remove it from sale instead.';
  end if;

  delete from public.products where id = p_product_id;

  if not found then
    raise exception 'That flavour was not found.';
  end if;
end;
$$;

revoke all on function public.create_product(text, text, int, text, text, int) from public, anon;
revoke all on function public.delete_product(uuid) from public, anon;
grant execute on function public.create_product(text, text, int, text, text, int) to authenticated;
grant execute on function public.delete_product(uuid) to authenticated;
