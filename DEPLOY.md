# Making Taste & See publicly available (HTTPS)

The storefront is a static site in `/frontend`. It talks to Supabase directly,
so any static host works. This guide covers the free options: **Netlify** and
**Cloudflare Pages**, both of which give a free `https://…` link for everyone and
support a custom domain later.

> **About `https://Taste&See.com`:** that is not a valid domain — `&` is not an
> allowed character in a hostname. The valid spellings (`tasteandsee.com`,
> `tastesee.com`, `taste-see.com`) are already registered by other people, so
> they cannot be used without buying them from the current owner. Any custom
> domain must be one **you own**, and its DNS must be pointed at the host.

Until a domain is connected, both hosts give a public HTTPS URL on their own
subdomain (for example `https://taste-and-see.netlify.app`).

---

## Option A — Netlify (recommended, ~2 minutes)

The repo already contains `netlify.toml`, which tells Netlify to publish the
`frontend` folder with no build step.

1. Sign in at <https://app.netlify.com> (free, Google login works).
2. **Add new site → Import an existing project → GitHub**.
3. Authorize Netlify for the `kennethperas15-cpu/tastesee` repository.
4. Confirm the settings (they come from `netlify.toml`):
   - **Branch to deploy:** `main`
   - **Build command:** *(empty)*
   - **Publish directory:** `frontend`
5. Click **Deploy site**. After a minute you get a public HTTPS link such as
   `https://taste-and-see.netlify.app`.

**Custom domain (later):** in the site settings open **Domain management → Add
a domain you own**, enter your domain, and follow the DNS instructions. Netlify
issues the HTTPS certificate automatically.

---

## Option B — Cloudflare Pages

The repo also contains `wrangler.toml` with the output folder.

1. Sign in at <https://dash.cloudflare.com>.
2. **Workers & Pages → Create → Pages → Connect to Git**.
3. Pick the `kennethperas15-cpu/tastesee` repository.
4. Use these build settings:
   - **Framework preset:** None
   - **Build command:** *(leave empty)*
   - **Build output directory:** `frontend`
5. **Save and Deploy**. You get a public HTTPS link such as
   `https://taste-and-see.pages.dev`.

**Custom domain (later):** open the Pages project → **Custom domains → Set up a
custom domain**, enter your domain, and add the DNS record Cloudflare shows.
The HTTPS certificate is issued automatically.

---

## Option C — Direct upload (no Git connection)

If you would rather upload the files by hand:

- **Netlify:** <https://app.netlify.com/drop> and drag the `frontend` folder in.
- **Cloudflare Pages:** Create a Pages project with **Direct Upload** and upload
  the `frontend` folder (or a zip of it).

This is quick for a test but the Git options above redeploy automatically when
the repository changes.

---

## What must stay private

Only the `frontend` folder is published. The `backend/` folder contains the
database migration (`backend/supabase/schema.sql`) and must **not** be exposed
by the host. Keep the publish/output directory set to `frontend` exactly as the
config files specify.

The browser key in `frontend/js/supabase-config.js` is the public “publishable”
key, which is safe to ship. Never put a `service_role`/secret key in the
frontend.
