# Weather Station plan excerpt

## Tasks

### Task 8: Upload relay

No repo test can reach the hosted relay. Verification is the staging Preview plus curl.

**Files:**

- Create: `relay/upload.js`

- [ ] **Step 1: Write the relay handler**

```js
// Accepts one reading per request and forwards it to storage.
export default async function handle(request) { return new Response(null, { status: 204 }); }
```

- [ ] **Step 2: Deploy to staging.**
- [ ] **Step 3: Verify in the staging Preview**:

```bash
curl -i -X POST "https://relay.example.com/readings" -d '{"temperature":21.5}'
# expect 204
```

- [ ] **Step 4: Commit** (ask first): `feat(relay): upload handler`
