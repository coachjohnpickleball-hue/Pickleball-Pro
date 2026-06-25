# Optional: Create a Separate Staging KV Namespace

For full isolation, create a second KV namespace in Cloudflare:

```bash
cd worker
npx wrangler kv namespace create USAGE --env staging
```

Copy the returned KV namespace id into:

```toml
[[env.staging.kv_namespaces]]
binding = "USAGE"
id = "PASTE_STAGING_KV_ID_HERE"
```

Then deploy staging:

```bash
npm run deploy:staging
```
