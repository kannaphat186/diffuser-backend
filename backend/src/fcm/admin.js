// src/fcm/admin.js — v6.0.0
// ─────────────────────────────────────────────────────────────
// Firebase Admin initialization. The service-account JSON is
// NEVER read from a path inside the repo. Three accepted sources,
// in priority order:
//
//   1. FIREBASE_SERVICE_ACCOUNT_JSON — the full JSON as a single
//      env var value. Convenient for Render / Fly / Railway which
//      let you paste secrets directly into the dashboard.
//
//   2. GOOGLE_APPLICATION_CREDENTIALS — path to a JSON file on
//      disk. Standard Google convention; the file must live
//      OUTSIDE the source tree (e.g. /etc/secrets/firebase.json
//      via Render's Secret Files feature).
//
//   3. backend/firebase-service-account.json — default local
//      development path. If present, used automatically. The
//      file is listed in .gitignore so it never ends up in source
//      control.
//
// If none are found we log a warning and push-sending becomes a
// no-op, but the rest of the backend continues to function.
// ─────────────────────────────────────────────────────────────
const fs = require('fs');
const path = require('path');

let adminApp = null;
let initTried = false;

function log(level, msg) {
  const stream = level === 'error' ? process.stderr : process.stdout;
  stream.write(`[FCM] ${msg}\n`);
}

function loadCredential() {
  const inlineJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (inlineJson && inlineJson.trim().length > 0) {
    try {
      return JSON.parse(inlineJson);
    } catch (err) {
      log('error', `FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON: ${err.message}`);
      return null;
    }
  }

  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (credPath) {
    try {
      const abs = path.isAbsolute(credPath) ? credPath : path.resolve(process.cwd(), credPath);
      const raw = fs.readFileSync(abs, 'utf8');
      return JSON.parse(raw);
    } catch (err) {
      log('error', `cannot read GOOGLE_APPLICATION_CREDENTIALS: ${err.message}`);
      return null;
    }
  }

  // Fallback: backend/firebase-service-account.json in project root.
  // Expected layout:
  //   backend/
  //     package.json
  //     firebase-service-account.json   ← here
  //     src/
  const localPath = path.resolve(__dirname, '..', '..', 'firebase-service-account.json');
  if (fs.existsSync(localPath)) {
    try {
      const raw = fs.readFileSync(localPath, 'utf8');
      return JSON.parse(raw);
    } catch (err) {
      log('error', `cannot read ${localPath}: ${err.message}`);
      return null;
    }
  }

  return null;
}

function init() {
  if (initTried) return adminApp;
  initTried = true;

  let admin;
  try {
    admin = require('firebase-admin');
  } catch (_) {
    log('warn', 'firebase-admin is not installed — push notifications disabled. Run: npm install firebase-admin');
    return null;
  }

  const cred = loadCredential();
  if (!cred) {
    log('warn',
      'no Firebase credential found — push notifications disabled. Provide ONE of:\n' +
      '       1) FIREBASE_SERVICE_ACCOUNT_JSON env var (the JSON as a string)\n' +
      '       2) GOOGLE_APPLICATION_CREDENTIALS env var (path to JSON file)\n' +
      '       3) backend/firebase-service-account.json file (local dev default)');
    return null;
  }

  try {
    adminApp = admin.initializeApp({
      credential: admin.credential.cert(cred),
      projectId: cred.project_id,
    });
    log('info', `✅ Firebase Admin initialized (project=${cred.project_id})`);
    return adminApp;
  } catch (err) {
    log('error', `Firebase Admin init failed: ${err.message}`);
    return null;
  }
}

function getAdmin() {
  if (!adminApp) init();
  if (!adminApp) return null;
  return require('firebase-admin');
}

function isReady() {
  if (!adminApp) init();
  return adminApp !== null;
}

module.exports = { init, getAdmin, isReady };
