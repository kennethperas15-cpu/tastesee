// All authentication, catalog, orders, and staff operations use Supabase.
const customerNameFromUser = user => user.user_metadata?.full_name
  || user.user_metadata?.name
  || [user.user_metadata?.given_name, user.user_metadata?.family_name].filter(Boolean).join(" ")
  || "";

function supa() { return window.supabaseClient || null; }

async function requireSupabase() {
  const client = supa();
  if (!window.TASTESEE_SUPABASE_URL || !window.TASTESEE_SUPABASE_ANON_KEY || !client) {
    throw new Error("Taste & See is not connected. Configure the Supabase project URL and publishable key before use.");
  }
  return client;
}

async function requireUser(client) {
  const { data: { user }, error } = await client.auth.getUser();
  if (error) throw error;
  if (!user) throw new Error("Sign in with Google to continue.");
  return user;
}

async function requireStaff(allowedRoles) {
  const client = await requireSupabase();
  const user = await requireUser(client);
  const { data, error } = await client.from("staff_access").select("role").eq("user_id", user.id).maybeSingle();
  if (error) throw error;
  if (!data || !allowedRoles.includes(data.role)) throw new Error("This Google account is not assigned to this staff workspace.");
  return { client, user, staff: { id: user.id, email: user.email, role: data.role } };
}

window.TasteSeeDB = {
  mode: () => supa() ? "supabase" : "unconfigured",
  signInWithGoogle: async redirectTo => {
    const client = await requireSupabase();
    const { error } = await client.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo, queryParams: { prompt: "select_account" } },
    });
    if (error) throw error;
  },
  currentCustomer: async () => {
    const client = await requireSupabase();
    const { data: { user }, error: authError } = await client.auth.getUser();
    if (authError) throw authError;
    if (!user) return null;
    const { data: staff, error } = await client.from("staff_access").select("role").eq("user_id", user.id).maybeSingle();
    if (error) throw error;
    if (staff) return null;
    return { id: user.id, email: user.email, name: customerNameFromUser(user), phone: user.user_metadata?.phone || "", role: "customer" };
  },
  currentStaff: async allowedRoles => {
    const client = await requireSupabase();
    const { data: { user }, error: authError } = await client.auth.getUser();
    if (authError) throw authError;
    if (!user) return null;
    const { data, error } = await client.from("staff_access").select("role").eq("user_id", user.id).maybeSingle();
    if (error) throw error;
    if (!data || !allowedRoles.includes(data.role)) {
      const { error: signOutError } = await client.auth.signOut();
      if (signOutError) throw signOutError;
      throw new Error("This Google account is not assigned to this staff workspace.");
    }
    return { id: user.id, email: user.email, role: data.role };
  },
  signOut: async () => {
    const client = await requireSupabase();
    const { error } = await client.auth.signOut();
    if (error) throw error;
  },
  staffAccess: async () => {
    const { client } = await requireStaff(["admin"]);
    const { data, error } = await client.rpc("list_staff_access");
    if (error) throw error;
    return data || [];
  },
  setStaffRole: async (email, role) => {
    const { client } = await requireStaff(["admin"]);
    const { error } = await client.rpc("set_staff_access", { p_email: email, p_role: role });
    if (error) throw error;
  },
  revokeStaffRole: async email => {
    const { client } = await requireStaff(["admin"]);
    const { error } = await client.rpc("remove_staff_access", { p_email: email });
    if (error) throw error;
  },
  signOutCustomer: async () => window.TasteSeeDB.signOut(),
  products: async () => {
    const client = await requireSupabase();
    const { data, error } = await client.from("products")
      .select("id,name,description,price_cents,emoji,category,stock_daily")
      .eq("is_active", true).order("name");
    if (error) throw error;
    if (!data?.length) throw new Error("The live menu is empty. Add active products in Supabase before accepting orders.");
    return data;
  },
  pools: async () => {
    const client = await requireSupabase();
    const { data, error } = await client.from("bake_pools").select("*")
      .gte("slot_time", new Date(new Date().setHours(0, 0, 0, 0)).toISOString())
      .order("slot_time").limit(6);
    if (error) throw error;
    return data || [];
  },
  createOrder: async order => {
    const client = await requireSupabase();
    const customer = await window.TasteSeeDB.currentCustomer();
    if (!customer) throw new Error("Sign in with a customer Google account before placing an order.");
    const { data, error } = await client.rpc("create_order", {
      p_customer_name: order.customer_name,
      p_phone: order.phone || "",
      p_kind: order.kind,
      p_address: order.address || "",
      p_delivery_lat: order.delivery_lat ?? null,
      p_delivery_lng: order.delivery_lng ?? null,
      p_delivery_distance_meters: order.delivery_distance_meters || 0,
      p_delivery_fee_cents: order.delivery_fee_cents || 0,
      p_subtotal_cents: order.subtotal_cents,
      p_discount_cents: order.discount_cents,
      p_total_cents: order.total_cents,
      p_pool_id: order.pool_id || null,
      p_estimated_ready_at: order.estimated_ready_at || null,
      p_items: order.items.map(item => ({
        name: item.name,
        qty: item.qty,
        unit_price_cents: item.unit_price_cents,
        custom: item.custom || {},
      })),
    });
    if (error) throw error;
    return { ...order, id: data, customer_id: customer.id, created_at: new Date().toISOString(), status: "pending" };
  },
  orders: async () => {
    const client = await requireSupabase();
    const { data, error } = await client.from("orders").select("*, order_items(*)")
      .order("created_at", { ascending: false }).limit(100);
    if (error) throw error;
    return (data || []).map(o => ({
      id: o.id, customer_id: o.customer_id, customer_name: o.customer_name, kind: o.kind,
      phone: o.phone, address: o.address, delivery_lat: o.delivery_lat, delivery_lng: o.delivery_lng,
      delivery_distance_meters: o.delivery_distance_meters, delivery_fee_cents: o.delivery_fee_cents,
      driver_id: o.driver_id, driver_lat: o.driver_lat, driver_lng: o.driver_lng,
      pool_id: o.pool_id, is_pool_order: o.is_pool_order, status: o.status, total_cents: o.total_cents,
      created_at: o.created_at, items: o.order_items || [],
    }));
  },
  trackOrders: async (customerName, orderId) => {
    const client = await requireSupabase();
    const customer = await window.TasteSeeDB.currentCustomer();
    if (!customer) throw new Error("Sign in with the Google account used to place the order.");
    const { data, error } = await client.rpc("track_orders", {
      p_customer_name: customerName, p_order_id: orderId,
    });
    if (error) throw error;
    return data || [];
  },
  setStatus: async (id, status) => {
    const client = await requireSupabase();
    const { data, error } = await client.from("orders").update({ status }).eq("id", id).select("id").maybeSingle();
    if (error) throw error;
    if (!data) throw new Error("The order was not updated. Your account may not have permission, or its status has changed.");
  },
  staffProducts: async () => {
    const { client } = await requireStaff(["admin", "baker"]);
    const { data, error } = await client.from("products")
      .select("id,name,price_cents,emoji,stock_daily,is_active").order("name");
    if (error) throw error;
    return data || [];
  },
  updateProductStock: async (id, stockDaily, isActive) => {
    const stock = Number(stockDaily);
    if (!id || !Number.isInteger(stock) || stock < 0 || stock > 500) {
      throw new Error("Daily stock must be a whole number from 0 to 500.");
    }
    const { client } = await requireStaff(["admin", "baker"]);
    const { error } = await client.rpc("update_product_stock", {
      p_product_id: id, p_stock_daily: stock, p_is_active: !!isActive,
    });
    if (error) throw error;
  },
  createStockNotice: async ({ productId, kind, message }) => {
    const text = String(message || "").trim();
    if (!["stop_restock", "low_stock", "note"].includes(kind)) throw new Error("Choose a notice type.");
    if (text.length < 3 || text.length > 280) throw new Error("Message must be 3–280 characters.");
    const { client } = await requireStaff(["admin", "baker"]);
    const { error } = await client.rpc("create_stock_notice", {
      p_product_id: productId || null, p_kind: kind, p_message: text,
    });
    if (error) throw error;
  },
  stockNotices: async () => {
    const { client } = await requireStaff(["admin", "baker"]);
    const { data, error } = await client.rpc("list_stock_notices");
    if (error) throw error;
    return data || [];
  },
  resolveStockNotice: async id => {
    const { client } = await requireStaff(["admin"]);
    const { error } = await client.rpc("resolve_stock_notice", { p_notice_id: id });
    if (error) throw error;
  },
  createProduct: async ({ name, description, priceCents, emoji, category, stockDaily }) => {
    const cleanName = String(name || "").trim();
    const price = Number(priceCents);
    const stock = Number(stockDaily);
    if (cleanName.length < 2 || cleanName.length > 60) throw new Error("Flavour name must be 2–60 characters.");
    if (!Number.isInteger(price) || price < 100 || price > 100000) throw new Error("Price must be between ₱1 and ₱1,000.");
    if (!Number.isInteger(stock) || stock < 0 || stock > 500) throw new Error("Daily stock must be between 0 and 500.");
    const { client } = await requireStaff(["admin", "baker"]);
    const { error } = await client.rpc("create_product", {
      p_name: cleanName, p_description: String(description || "").trim().slice(0, 200),
      p_price_cents: price, p_emoji: String(emoji || "").trim().slice(0, 8) || null,
      p_category: String(category || "").trim().slice(0, 30) || null, p_stock_daily: stock,
    });
    if (error) throw error;
  },
  deleteProduct: async id => {
    if (!id) throw new Error("Choose a flavour to delete.");
    const { client } = await requireStaff(["admin"]);
    const { error } = await client.rpc("delete_product", { p_product_id: id });
    if (error) throw error;
  },
  sendStaffMessage: async ({ targetRole, body, orderId }) => {
    const text = String(body || "").trim();
    if (!["admin", "baker", "driver"].includes(targetRole)) throw new Error("Choose who to message.");
    if (text.length < 1 || text.length > 500) throw new Error("Message must be 1–500 characters.");
    const { client } = await requireStaff(["admin", "baker", "driver"]);
    const { error } = await client.rpc("send_staff_message", {
      p_target_role: targetRole, p_body: text, p_order_id: orderId || null,
    });
    if (error) throw error;
  },
  staffMessages: async () => {
    const { client } = await requireStaff(["admin", "baker", "driver"]);
    const { data, error } = await client.rpc("list_staff_messages");
    if (error) throw error;
    return data || [];
  },
  assignDriver: async orderId => {
    const { client, user } = await requireStaff(["driver"]);
    const { data, error } = await client.from("orders")
      .update({ status: "out_for_delivery", driver_id: user.id })
      .eq("id", orderId).eq("kind", "delivery").eq("status", "ready").is("driver_id", null)
      .select("id").maybeSingle();
    if (error) throw error;
    if (!data) throw new Error("This delivery was already accepted or is no longer available.");
  },
  updateDriverLocation: async (orderId, lat, lng) => {
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      throw new Error("A valid rider location is required.");
    }
    const { client, user } = await requireStaff(["driver"]);
    const { data, error } = await client.from("orders")
      .update({ driver_lat: lat, driver_lng: lng })
      .eq("id", orderId).eq("driver_id", user.id).eq("status", "out_for_delivery")
      .select("id").maybeSingle();
    if (error) throw error;
    if (!data) throw new Error("This delivery is no longer assigned to your rider account.");
  },
  getDriverOrders: async () => {
    const { client, user } = await requireStaff(["driver"]);
    const { data, error } = await client.from("orders").select("*, order_items(*)")
      .eq("kind", "delivery")
      .or(`status.eq.ready,and(driver_id.eq.${user.id},status.eq.out_for_delivery)`)
      .order("created_at", { ascending: true }).limit(100);
    if (error) throw error;
    return (data || []).map(o => ({
      id: o.id, customer_id: o.customer_id, customer_name: o.customer_name, phone: o.phone,
      address: o.address, kind: o.kind, status: o.status, total_cents: o.total_cents,
      delivery_lat: o.delivery_lat, delivery_lng: o.delivery_lng, driver_id: o.driver_id,
      driver_lat: o.driver_lat, driver_lng: o.driver_lng, created_at: o.created_at,
      items: o.order_items || [],
    }));
  },
  moments: async () => {
    const client = await requireSupabase();
    const { data, error } = await client.from("community_moments")
      .select("id,caption,location_tag,image_path,created_at")
      .order("created_at", { ascending: false }).limit(24);
    if (error) throw error;
    return (data || []).map(moment => ({
      ...moment,
      image_url: client.storage.from("community-moments").getPublicUrl(moment.image_path).data.publicUrl,
    }));
  },
  publishMoment: async ({ imageFile, caption = "", locationTag = "" }) => {
    if (caption.length > 160 || locationTag.length > 80) throw new Error("Caption or location is too long.");
    const customer = await window.TasteSeeDB.currentCustomer();
    if (!customer) throw new Error("Sign in with a customer Google account before sharing a photo.");
    if (typeof File === "undefined" || !(imageFile instanceof File)) throw new Error("Choose a photo to share.");
    if (!["image/jpeg", "image/png", "image/webp"].includes(imageFile.type)) throw new Error("Choose a JPEG, PNG, or WebP image.");
    const client = await requireSupabase();
    const extension = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" }[imageFile.type];
    const imagePath = `${customer.id}/${crypto.randomUUID()}.${extension}`;
    const bucket = client.storage.from("community-moments");
    const { error: uploadError } = await bucket.upload(imagePath, imageFile, { contentType: imageFile.type, upsert: false });
    if (uploadError) throw uploadError;
    const { error: insertError } = await client.from("community_moments").insert({
      user_id: customer.id, image_path: imagePath, caption: caption.trim(), location_tag: locationTag.trim(),
    });
    if (insertError) {
      const { error: cleanupError } = await bucket.remove([imagePath]);
      if (cleanupError) throw new Error(`Could not publish the photo (${insertError.message}); uploaded file cleanup also failed (${cleanupError.message}).`);
      throw insertError;
    }
  },
};
