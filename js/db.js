// Taste & See DB layer: Supabase if keys present, else localStorage fallback.
// Set window.TASTESEE_SUPABASE_URL + window.TASTESEE_SUPABASE_ANON_KEY before loading,
// or edit the consts below (or use admin Settings which stores them in localStorage).
const LS_ORDERS = "tastesee_orders_v1";
const LS_POOLS = "tastesee_pools_v1";

const FALLBACK_PRODUCTS = [
  { id: "classic", name: "Classic", description: "Soft, buttery dough with our signature cinnamon swirl.", price_cents: 9500, emoji: "🌀" },
  { id: "tiramisu", name: "Tiramisu", description: "Espresso-kissed cream and a cocoa finish.", price_cents: 14500, emoji: "☕" },
  { id: "biscoff", name: "Biscoff", description: "Caramelized biscuit spread with a golden crunch.", price_cents: 13500, emoji: "🍪" },
  { id: "oreo", name: "Oreo", description: "Cookies-and-cream filling with a chocolate crumble.", price_cents: 12500, emoji: "🍫" },
];

function supaKeys() {
  return {
    url: window.TASTESEE_SUPABASE_URL || localStorage.getItem("ts_sb_url") || "",
    key: window.TASTESEE_SUPABASE_ANON_KEY || localStorage.getItem("ts_sb_key") || "",
  };
}
function supa() { return window.supabaseClient || null; }
function useSupa() {
  const { url, key } = supaKeys();
  return !!(url && key && supa());
}
function lsGet(k, fb) { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : fb; } catch { return fb; } }
function lsSet(k, v) { localStorage.setItem(k, JSON.stringify(v)); }
const uid = () => (crypto.randomUUID ? crypto.randomUUID() : "id-" + Date.now() + "-" + Math.random().toString(16).slice(2));

function defaultPools() {
  const today = new Date(); today.setHours(0,0,0,0);
  const mk = (h, m, title, flavor, target) => {
    const d = new Date(today); d.setHours(h, m, 0, 0);
    return { id: uid(), title, flavor_focus: flavor, target_qty: target, joined_qty: 0,
      slot_time: d.toISOString(), status: "filling", discount_pct: 15 };
  };
  return [
    mk(8, 0, "Morning Warm Batch", "Classic · Tiramisu · Biscoff · Oreo", 12),
    mk(12, 30, "Lunch Melt Batch", "Classic · Tiramisu · Biscoff · Oreo", 16),
    mk(17, 0, "Sunset Cinna Batch", "Classic · Tiramisu · Biscoff · Oreo", 20),
  ];
}
function poolsWithRoll() {
  let pools = lsGet(LS_POOLS, null);
  const todayKey = new Date().toDateString();
  if (!pools || pools._day !== todayKey) {
    pools = { _day: todayKey, list: defaultPools() };
    lsSet(LS_POOLS, pools);
  }
  return pools.list;
}

async function requireSupabase() {
  if (!useSupa()) throw new Error("Staff access requires a configured Supabase project.");
  return supa();
}

window.TasteSeeDB = {
  mode: () => (useSupa() ? "supabase" : "local"),
  signIn: async (email, password, allowedRoles) => {
    const client = await requireSupabase();
    const { error: signInError } = await client.auth.signInWithPassword({ email, password });
    if (signInError) throw signInError;
    const { data: { user }, error: userError } = await client.auth.getUser();
    if (userError || !user) {
      await client.auth.signOut();
      throw userError || new Error("Could not verify the signed-in account.");
    }
    const { data, error } = await client.from("staff_access").select("role").eq("user_id", user.id).maybeSingle();
    if (error || !data || !allowedRoles.includes(data.role)) {
      await client.auth.signOut();
      if (error) throw error;
      throw new Error("This account is not assigned to this workspace.");
    }
    return { email: user.email, role: data.role };
  },
  currentStaff: async (allowedRoles) => {
    if (!useSupa()) return null;
    const client = supa();
    const { data: { user }, error: userError } = await client.auth.getUser();
    if (userError) throw userError;
    if (!user) return null;
    const { data, error } = await client.from("staff_access").select("role").eq("user_id", user.id).maybeSingle();
    if (error) throw error;
    if (!data || !allowedRoles.includes(data.role)) return null;
    return { email: user.email, role: data.role };
  },
  signOut: async () => {
    const client = await requireSupabase();
    const { error } = await client.auth.signOut();
    if (error) throw error;
  },
  products: async () => {
    if (useSupa()) {
      const { data, error } = await supa().from("products").select("*").eq("is_active", true);
      if (!error && data && data.length) return data.map(p => ({
        id: p.id, name: p.name, price_cents: p.price_cents, emoji: p.emoji || "🥯",
        description: p.description || "", stock_daily: p.stock_daily ?? 50 }));
      return FALLBACK_PRODUCTS;
    }
    return FALLBACK_PRODUCTS;
  },
  pools: async () => {
    if (useSupa()) {
      const { data, error } = await supa().from("bake_pools").select("*")
        .gte("slot_time", new Date(new Date().setHours(0,0,0,0)).toISOString())
        .order("slot_time").limit(6);
      if (!error && data && data.length) return data;
    }
    return poolsWithRoll();
  },
  joinPool: async (poolId, customerName, qty) => {
    if (useSupa()) {
      const { error } = await supa().rpc("join_bake_pool", {
        p_pool_id: poolId, p_customer_name: customerName, p_qty: qty, p_order_id: null,
      });
      if (error) throw error;
      return true;
    }
    const pools = lsGet(LS_POOLS, null); const list = pools?.list || defaultPools();
    const p = list.find(x => x.id === poolId); if (!p) return false;
    p.joined_qty += qty;
    if (p.joined_qty >= p.target_qty) p.status = "locked";
    lsSet(LS_POOLS, { _day: new Date().toDateString(), list });
    return true;
  },
  createOrder: async (order) => {
    const rec = { id: uid(), created_at: new Date().toISOString(), status: "pending", ...order };
    if (useSupa()) {
      const { data, error } = await supa().from("orders").insert({
        customer_name: rec.customer_name, phone: rec.phone, kind: rec.kind, address: rec.address,
        status: "pending", subtotal_cents: rec.subtotal_cents, discount_cents: rec.discount_cents,
        total_cents: rec.total_cents, pool_id: rec.pool_id || null, is_pool_order: !!rec.pool_id,
        estimated_ready_at: rec.estimated_ready_at || null,
      }).select("id").single();
      if (error) throw error;
      const oid = data.id;
      if (rec.items?.length) {
        const { error: itemsError } = await supa().from("order_items").insert(rec.items.map(it => ({
        order_id: oid, product_name: it.name, qty: it.qty, unit_price_cents: it.unit_price_cents,
        customizations: it.custom || {} })));
        if (itemsError) throw itemsError;
      }
      if (rec.pool_id) {
        const { error: poolError } = await supa().rpc("join_bake_pool", {
          p_pool_id: rec.pool_id, p_customer_name: rec.customer_name,
          p_qty: rec.items.reduce((a, i) => a + i.qty, 0), p_order_id: oid,
        });
        if (poolError) throw poolError;
      }
      rec.id = oid; return rec;
    }
    const all = lsGet(LS_ORDERS, []); all.unshift(rec); lsSet(LS_ORDERS, all);
    if (rec.pool_id) window.TasteSeeDB.joinPool(rec.pool_id, rec.customer_name, rec.items.reduce((a,i)=>a+i.qty,0));
    return rec;
  },
  orders: async () => {
    if (useSupa()) {
      const { data, error } = await supa().from("orders").select("*, order_items(*)").order("created_at", { ascending: false }).limit(100);
      if (error) throw error;
      return (data || []).map(o => ({ id: o.id, customer_name: o.customer_name, kind: o.kind,
        phone: o.phone, address: o.address, status: o.status, total_cents: o.total_cents,
        created_at: o.created_at, items: o.order_items || [] }));
    }
    return lsGet(LS_ORDERS, []);
  },
  trackOrders: async (customerName, orderId) => {
    if (useSupa()) {
      const { data, error } = await supa().rpc("track_orders", {
        p_customer_name: customerName, p_order_id: orderId,
      });
      if (error) throw error;
      return data || [];
    }
    return lsGet(LS_ORDERS, []).filter(o =>
      o.customer_name.toLowerCase() === customerName.toLowerCase() &&
      o.id.toLowerCase().startsWith(orderId.toLowerCase()));
  },
  setStatus: async (id, status) => {
    if (useSupa()) {
      const { error } = await supa().from("orders").update({ status }).eq("id", id);
      if (error) throw error;
      return;
    }
    const all = lsGet(LS_ORDERS, []); const o = all.find(x => x.id === id);
    if (o) { o.status = status; lsSet(LS_ORDERS, all); }
  },
  saveKeys: (url, key) => { localStorage.setItem("ts_sb_url", url); localStorage.setItem("ts_sb_key", key); location.reload(); },
};
