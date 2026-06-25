# Block / Remove Access

## Block everyone
Change the Terms version in `worker/src/index.js`:

```js
const TOS_VERSION = '2026-06-25';
```

Deploy to `rally`. Anyone who accepted an older version is blocked until they accept the new version.

## Block one user in the app
Open this admin page while logged in as an admin:

```
/admin/users
```

Use **Block User** to add an app-level block. Blocked users see an Access Blocked screen and API requests return `403`.

## Block one user at Cloudflare front door
For stronger blocking, also add a Cloudflare Zero Trust Access **Block** policy above the Allow policy.

## Force one user to reaccept Terms
Open:

```
/admin/users
```

Enter the email and click **Force Terms Reacceptance**. This deletes that user's current terms acceptance records in KV, so they must accept the current Terms again before app access.

## Static/env blocked users
You can also set comma-separated blocked users in `wrangler.toml`:

```toml
[env.rally.vars]
BLOCKED_USERS = "user1@example.com,user2@example.com"
```

Users blocked this way can only be unblocked by editing the env var and redeploying.
