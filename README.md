<p align="center"><img src="./frontend/assets/logo.png" alt="Taste & See logo" width="180" /></p>

# Taste & See — fresh buns, baked with love

Responsive Philippine-peso storefront for four fresh flavours: **Classic, Tiramisu, Biscoff, and Oreo**. Includes Supabase-backed online order requests, an admin dashboard, a baker production queue, a rider delivery station, and Taste & See Moments.

## Store experience
- Soft pastel styling, responsive menu filters, and reduced-motion support.
- A four-slot bun box with mix-and-match flavours and an inline order receipt.
- Google sign-in is required to place and track orders and to share a community photo.
- Delivery fee quotes use a ₱40 base fare plus ₱12 per road kilometre. Leaflet/OpenStreetMap provides the selectable Cebu City map; OSRM is used when available, with an approximate road-distance fallback.
- Customers can follow out-for-delivery orders on a live map. Rider coordinates are refreshed from the rider’s device while an assigned delivery is active.
- Online payments are not integrated. Orders are requests only; the storefront does not collect payment details or charge customers.

## Stack and layout
- **Supabase** — Google authentication, Postgres persistence, row-level security, and community photo storage.
- **Static frontend** — `frontend/` contains the customer storefront, staff workspaces, browser JavaScript, Python analytics source, and assets.
- **Database setup** — `backend/supabase/schema.sql` and `backend/supabase/seed.sql`.

There is no local/demo data mode. If Supabase is not configured or a live request fails, the affected screen reports an error rather than using browser storage or sample products.

## Run locally

Configure the Supabase and Google settings below first, then serve `frontend/` over HTTP. For example, from the repository root in PowerShell:

```powershell
python -m http.server 8000 --directory frontend
```

Open `http://localhost:8000/index.html`. Add the exact localhost callback paths to Supabase Authentication URL Configuration. Opening the files with `file://` is not supported for OAuth.

## Production setup

Complete these steps in a non-production/test Supabase project first. Back up production data before applying schema changes.

1. **Configure Supabase.** Create/select the project and review `backend/supabase/schema.sql`; run it in that project’s SQL Editor, then run `backend/supabase/seed.sql` to create the initial menu and bake pools. For an existing project, inspect the current schema and seed data before rerunning either file. Confirm the expected products and active prices in `public.products`.
2. **Set the browser connection.** For local testing, set the project URL and **publishable key** (or legacy anon key) in `frontend/js/supabase-config.js`. For GitHub Pages, the deployment workflow injects these from the `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` repository variables described below. The key is public and is safe to ship only with correctly configured row-level security. Never put a `service_role` key or Google client secret in frontend files. The application fails closed until the URL, key, and Supabase JS library are available.
3. **Enable Google OAuth.**
   - Create a Google OAuth client of type **Web application** in Google Cloud.
   - Add `https://kennethperas15-cpu.github.io` (and `http://localhost:8000` for local testing, if needed) to its authorized JavaScript origins.
   - In Supabase **Authentication → Providers → Google**, enable Google and enter the Google client ID and secret. Add the exact Supabase callback URI displayed on that page to the Google OAuth client's authorized redirect URIs.
   - In Supabase **Authentication → URL Configuration**, set the Site URL to `https://kennethperas15-cpu.github.io/tastesee/` and allow these exact redirect URLs: `https://kennethperas15-cpu.github.io/tastesee/index.html`, `https://kennethperas15-cpu.github.io/tastesee/admin.html`, `https://kennethperas15-cpu.github.io/tastesee/baker.html`, and `https://kennethperas15-cpu.github.io/tastesee/driver.html`. Add `http://localhost:8000/index.html`, `http://localhost:8000/admin.html`, `http://localhost:8000/baker.html`, and `http://localhost:8000/driver.html` as separate development redirect URLs only if needed.
4. **Create the first admin.** Open the deployed `/admin.html`, sign in once with the owner’s Google account, then run this one-time bootstrap in the Supabase SQL Editor, replacing the email with the exact owner account:
   ```sql
   do $$
   declare
     owner_user_id uuid;
   begin
     select id into owner_user_id
     from auth.users
     where lower(email) = lower('owner@example.com')
     limit 1;

     if owner_user_id is null then
       raise exception 'Sign in with the owner Google account before bootstrapping the first admin.';
     end if;

     insert into public.staff_access (user_id, role)
     values (owner_user_id, 'admin')
     on conflict (user_id) do update set role = excluded.role;
   end $$;
   ```
   Reload `/admin.html` and sign in again. The bootstrap SQL is for the initial owner only; thereafter, use **Manage staff access** in the admin workspace.
5. **Assign staff.** Have each trusted baker or rider sign in once at `/baker.html` or `/driver.html` using their Google account. The admin can then enter that account’s Google email and assign the `baker` or `driver` role. Only admins can list, assign, or revoke roles. Do not assign roles to untrusted accounts.
6. **Configure and deploy GitHub Pages.** In the repository’s **Settings → Secrets and variables → Actions → Variables**, create `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` using the Supabase project URL and public publishable/anon key. These values are included in the browser build; never use a service-role key. Under **Settings → Pages**, choose **GitHub Actions** as the build and deployment source. The workflow at `.github/workflows/pages.yml` deploys the `frontend/` directory on pushes to `main` and can be run manually. It fails rather than publishing if either variable is missing. The default site address is `https://kennethperas15-cpu.github.io/tastesee/`; if you configure a custom domain, update the URLs in Google OAuth and Supabase to that domain before testing sign-in.
7. **Verify before opening the store.** Test a customer sign-in and order, owner-only order tracking, baker status changes, rider assignment/location/delivery completion, and admin role assignment/revocation. In Supabase, run the Database Security Advisor and review Auth URL settings, RLS policies, storage policies, and database logs. Confirm no browser request contains a service-role key.

The public storefront intentionally has no staff navigation button. Staff URLs remain protected workspaces: signing in with Google alone does not grant staff access, and Supabase policies/RPCs enforce assigned roles and order ownership. Existing browser-only demo orders are not migrated; only orders created through the configured Supabase-backed site are available.

## Admin analytics

`/admin.html` requires an assigned admin account. It includes order and revenue summaries, live order controls, bake-pool status, best sellers, and a demand forecast calculated from the order history returned by Supabase.
