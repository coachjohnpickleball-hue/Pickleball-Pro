# Admin Visibility and Access Control

This build hides Admin UI from non-admin users and keeps server-side admin routes protected.

## Admin users
Configured in `worker/wrangler.toml`:

```toml
ADMIN_EMAILS = "coachjohnpickleball@gmail.com"
```

For multiple admins, use comma-separated emails:

```toml
ADMIN_EMAILS = "coachjohnpickleball@gmail.com,johnmergulhao@gmail.com"
```

## What changed
- Non-admin users do not see the Admin tab / Admin Lock shortcut.
- Non-admin users do not see Access Log links.
- Direct visits to `/admin/tos-status`, `/admin/users`, `/admin/access-log`, and `/admin/login-log` are still blocked server-side unless the Cloudflare Access email is in `ADMIN_EMAILS`.
- The app injects the logged-in Cloudflare Access email into the page only as a minimal admin/non-admin flag.

## Deploy

```bash
cd worker
npm install
npm run deploy:rally
```
