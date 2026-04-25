# Scent & Sense Backend — Deployment Guide (v5.2.5)

Target environment: **Render** (Web Service) + **MongoDB Atlas**.
Node.js 18+.

This document is the source of truth for deployment. If it disagrees
with a changelog, this document wins.

---

## 1. Render service configuration

Repository: this repo. Root: `backend/`.

| Render setting         | Value                                    |
|------------------------|------------------------------------------|
| Environment            | Node                                     |
| Region                 | Singapore (closest to TH)                |
| Build command          | `npm ci --omit=dev`                      |
| Start command          | `npm start`                              |
| Health check path      | `/health`                                |
| Auto-deploy            | On (main branch), or manual — your call  |

`npm start` runs `NODE_ENV=production node src/server.js`, which in
turn enables the CORS allowlist enforcement added in v5.2.5.

### Required environment variables

Configure these in Render → **Environment**. Never paste them into
source control, never paste them into Slack.

| Variable                       | Required | Example                                    |
|--------------------------------|----------|--------------------------------------------|
| `NODE_ENV`                     | ✅       | `production`                               |
| `MONGODB_URI`                  | ✅       | `mongodb+srv://<user>:<pass>@<cluster>/diffuser_db?retryWrites=true&w=majority` |
| `JWT_SECRET`                   | ✅       | 48+ random bytes hex (see generation below) |
| `DEVICE_TOKEN_REQUIRED`        | ✅       | `true`                                     |
| `DEVICE_SHARED_SECRET`         | ✅       | matches firmware `FACTORY_TOKEN` / per-device token |
| `CORS_ALLOWED_ORIGINS`         | ✅       | `https://diffuser-backend-1.onrender.com`  |
| `LOG_LEVEL`                    | optional | `info`                                     |
| `DEVICE_OFFLINE_THRESHOLD_MS`  | optional | `180000`                                   |
| `OFFLINE_NOTIFICATION_GRACE_MS`| optional | `30000`                                    |

Render injects `PORT` automatically. Do not set it yourself.

Generate a fresh `JWT_SECRET`:

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"