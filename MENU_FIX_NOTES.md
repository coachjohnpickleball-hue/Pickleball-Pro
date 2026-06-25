# Menu/TOML Fix

This build adds a hardened global `showTab()` plus capture-phase menu click handling so navigation buttons work even if one tab render function has an issue.

Deploy:

```bash
cd worker
npm install
npx wrangler deploy --env rally
```
