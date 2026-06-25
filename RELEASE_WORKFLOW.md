# Pickleball Pro Release Workflow

Use this workflow so `rally` stays stable.

## Environments

- `staging` → Cloudflare Worker name `rally-staging`
- `rally` → production Cloudflare Worker name `rally`

## Safe release process

From the extracted package:

```bash
cd worker
npm install
npm run check
npm run dry-run:staging
npm run deploy:staging
```

Test staging in the browser. Only after it passes:

```bash
npm run dry-run:rally
npm run deploy:rally
```

## Minimum manual test before production

- Login through Cloudflare Access
- Terms gate blocks users who have not accepted
- Accept & Continue records the current version
- Main menu opens each key screen
- Add/edit player
- Generate round
- Start round
- Enter score
- Standings update
- Live display opens
- Fairness panel opens
- Admin Access Log opens
- Admin TOS Status opens
- Export still works

## Notes

The staging environment currently points to the same KV namespace as production so the package deploys without requiring a new Cloudflare setup step. For true isolation, create a separate KV namespace in Cloudflare and replace the `id` under `[[env.staging.kv_namespaces]]` in `worker/wrangler.toml`.
