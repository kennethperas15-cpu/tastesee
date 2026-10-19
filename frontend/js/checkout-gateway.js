// ORDERING / CHECKOUT GATEWAY — Step 2 of the customer flow.
//
// This module deliberately knows nothing about flavours, the catalogue, the
// menu, or how the cart is rendered. It receives an already-committed order
// snapshot from the flavour step and is solely responsible for:
//   • quantity validation (1–10 boxes)
//   • the daily slot gate
//   • device + location duplicate detection
//   • the checkout preflight and the final create_order call
//
// Keeping these rules here means flavour customisation can evolve without
// touching checkout restrictions, and the restrictions cannot be bypassed by
// the flavour UI.
(function () {
  const MAX_BOXES = 10;
  const LIMIT_MESSAGE = "Order Limit Reached: You can only purchase a maximum of 10 boxes per order.";
  const RPC_MISSING = /PGRST202|Could not find the function|schema cache/i;

  let cachedClientIp = null;

  function showLimitModal() {
    const dialog = document.getElementById("orderLimitDlg");
    if (dialog && typeof dialog.showModal === "function") {
      if (!dialog.open) dialog.showModal();
      return;
    }
    window.alert(LIMIT_MESSAGE);
  }

  function describeDevice() {
    const ua = navigator.userAgent || "";
    const android = ua.match(/Android[^;]*;\s*([^;)]*?)(?:\s+Build\/|\))/i);
    if (android && android[1]) return `Android · ${android[1].trim()}`;
    const iphone = ua.match(/iPhone(?:\s+OS\s+([\d_]+))?/i);
    if (iphone) return `iPhone${iphone[1] ? ` · iOS ${iphone[1].replace(/_/g, ".")}` : ""}`;
    if (/iPad/i.test(ua)) return "iPad";
    if (/Windows/i.test(ua)) return "Windows PC";
    if (/Macintosh|Mac OS X/i.test(ua)) return "Mac";
    if (/Linux/i.test(ua)) return "Linux device";
    return navigator.platform || "Unknown device";
  }

  function deviceSignature() {
    return [
      navigator.userAgent || "",
      navigator.platform || "",
      typeof screen !== "undefined" ? `${screen.width}x${screen.height}x${screen.colorDepth}` : "",
      Intl.DateTimeFormat().resolvedOptions().timeZone || "",
      navigator.language || "",
      navigator.hardwareConcurrency || "",
      navigator.deviceMemory || "",
      navigator.maxTouchPoints || 0,
    ].join("|");
  }

  async function fetchClientIp() {
    if (cachedClientIp !== null) return cachedClientIp;
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 2500);
      const response = await fetch("https://api.ipify.org?format=json", { cache: "no-store", signal: controller.signal });
      clearTimeout(timer);
      if (!response.ok) throw new Error("IP lookup failed");
      const data = await response.json();
      cachedClientIp = /^[0-9a-fA-F:.]{3,45}$/.test(data.ip || "") ? data.ip : "";
    } catch {
      cachedClientIp = "";
    }
    return cachedClientIp;
  }

  async function approximateLocation() {
    if (!navigator.geolocation) return null;
    return new Promise(resolve => {
      navigator.geolocation.getCurrentPosition(
        position => resolve(position),
        () => resolve(null),
        { enableHighAccuracy: false, timeout: 4000, maximumAge: 300000 }
      );
    });
  }

  // Customer location + phone/device metadata, captured at checkout only.
  async function collectMetadata({ kind, delivery, address }) {
    const ip = await fetchClientIp();
    let locationKey = null;
    let locationSource = null;

    if (kind === "delivery" && delivery && Number.isFinite(Number(delivery.lat)) && Number.isFinite(Number(delivery.lng))) {
      locationKey = `delivery:${Number(delivery.lat).toFixed(4)},${Number(delivery.lng).toFixed(4)}`;
      locationSource = "delivery-pin";
    } else if (kind === "delivery") {
      const normalized = String(address || "").trim().replace(/\s+/g, " ").toLowerCase();
      if (normalized) {
        locationKey = `address:${normalized}`;
        locationSource = "address";
      }
    }

    if (!locationKey && ip) {
      locationKey = `ip:${ip}`;
      locationSource = "ip";
    }

    if (!locationKey) {
      const position = await approximateLocation();
      if (position) {
        locationKey = `geo:${position.coords.latitude.toFixed(4)},${position.coords.longitude.toFixed(4)}`;
        locationSource = "geolocation";
      }
    }

    return {
      device_key: deviceSignature(),
      device_model: describeDevice(),
      location_key: locationKey,
      location_source: locationSource,
      client_ip: ip || null,
    };
  }

  // Read-only "middleware" check. The create_order RPC repeats all of these
  // checks atomically, so this preflight is advisory only.
  async function preflight({ boxCount, metadata }) {
    const client = window.supabaseClient;
    if (!client) throw new Error("The storefront is not connected.");
    const { data, error } = await client.rpc("check_order_gateway", {
      p_box_count: boxCount,
      p_device_key: metadata.device_key || null,
      p_location_key: metadata.location_key || null,
    });
    // Until the backend migration is applied the RPC may not exist yet.
    // In that case defer to create_order, which remains authoritative.
    if (error) {
      if (RPC_MISSING.test(String(error.message || "")) || error.code === "PGRST202") return { allowed: true, code: "unverified" };
      throw error;
    }
    return data || { allowed: true, code: "ok" };
  }

  function errorWithCode(message, code) {
    const error = new Error(message);
    error.code = code;
    return error;
  }

  async function submit({ name, phone, kind, address, delivery, boxCount, items, subtotalCents, discountCents, totalCents, estimatedReadyAt }) {
    const boxes = Number(boxCount);
    const bunCount = (items || []).reduce((sum, item) => sum + (Number(item.qty) || 0), 0);
    if (!Number.isInteger(boxes) || boxes < 1) throw errorWithCode("Add at least one box before placing your order.", "empty");
    if (boxes > MAX_BOXES) throw errorWithCode(LIMIT_MESSAGE, "order_limit");
    if (bunCount !== boxes * 4) throw errorWithCode("Each box must hold exactly 4 buns before checkout.", "incomplete_box");

    const metadata = await collectMetadata({ kind, delivery: delivery || {}, address });
    const decision = await preflight({ boxCount: boxes, metadata });
    if (!decision.allowed) throw errorWithCode(decision.message || "Checkout validation failed.", decision.code || "blocked");

    const order = await window.TasteSeeDB.createOrder({
      customer_name: name,
      phone,
      kind,
      address: kind === "delivery" ? address : "",
      delivery_lat: kind === "delivery" ? (delivery?.lat ?? null) : null,
      delivery_lng: kind === "delivery" ? (delivery?.lng ?? null) : null,
      delivery_distance_meters: 0,
      delivery_fee_cents: 0,
      box_count: boxes,
      subtotal_cents: subtotalCents,
      discount_cents: discountCents,
      total_cents: totalCents,
      pool_id: null,
      estimated_ready_at: estimatedReadyAt,
      ...metadata,
      items: (items || []).map(item => ({
        name: item.name,
        qty: item.qty,
        unit_price_cents: item.unit_price_cents,
        custom: item.custom || {},
      })),
    });

    return { order, metadata };
  }

  window.TasteSeeCheckout = {
    MAX_BOXES,
    LIMIT_MESSAGE,
    showLimitModal,
    collectMetadata,
    submit,
  };
})();
