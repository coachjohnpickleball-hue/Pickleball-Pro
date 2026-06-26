# Admin/Terms Real Fix Notes

This build patches the actual rendered `worker/src/app.html` and Worker route layer.

## Admin tab/menu fix
- Non-admin pages are marked with `html.pb-non-admin-root` and `body.pb-non-admin` by the Worker.
- Admin-only buttons/links/sections are removed server-side for non-admin users where possible.
- A final client-side guard also hides any admin elements that are generated later.
- `showTab('admin')` is blocked for non-admin users.
- Admin status is now derived from the logged-in Cloudflare Access email and `ADMIN_EMAILS`.

## Terms version control
- Admins can open `/admin/terms-settings`.
- Updating the Terms version forces every user to reaccept before using the app.
- Current admin email in `wrangler.toml`: `coachjohnpickleball@gmail.com`.

## Troubleshooting
Open `/whoami` while logged in. It shows the email Cloudflare Access is passing to the Worker and whether the app considers that user an admin.
