window.TASTESEE_SUPABASE_URL = "https://ubjpsjndtzlpugvxduhr.supabase.co";
window.TASTESEE_SUPABASE_ANON_KEY = "";

if (!window.TASTESEE_SUPABASE_URL || !window.TASTESEE_SUPABASE_ANON_KEY || !window.supabase) {
  console.error("Taste & See production configuration is incomplete. Set the Supabase URL and publishable key in frontend/js/supabase-config.js.");
} else {
  window.supabaseClient = window.supabase.createClient(
    window.TASTESEE_SUPABASE_URL,
    window.TASTESEE_SUPABASE_ANON_KEY
  );
}
