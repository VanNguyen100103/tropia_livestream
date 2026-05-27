# Android App Links — deployment checklist

The Android app has an `autoVerify="true"` intent filter on
`https://tropia.vn/auth/*` (see `app/src/main/AndroidManifest.xml`).
Without a matching `assetlinks.json` at the verified URL, Android treats
the link as unverified and falls back to the "Open with" chooser — which
is exactly the attack vector App Links is meant to close. Follow the
steps below before the next signed release.

## 1. Get the SHA-256 fingerprint of the signing key

For a locally signed release:

```bash
keytool -list -v -keystore <path-to-keystore.jks> -alias <alias> \
  | grep "SHA256:"
```

For Play App Signing (Google manages the upload key for you):

1. Play Console → Setup → App integrity → App signing
2. Copy the **SHA-256 certificate fingerprint** under "App signing key
   certificate".
3. Also copy the upload key fingerprint and add it as a second entry —
   internal test tracks and debug-on-device installs still use the
   upload key, so without it App Links verification fails on testers'
   phones.

## 2. Fill in `assetlinks.json`

Replace the two placeholders in [assetlinks.json](./assetlinks.json):

```json
"sha256_cert_fingerprints": [
  "AB:CD:EF:...",   ← release / Play app signing key
  "12:34:56:..."    ← upload key (Play App Signing only)
]
```

If only one key applies, leave the array with a single entry.

## 3. Deploy at the verified URL

The file MUST be served from:

```
https://tropia.vn/.well-known/assetlinks.json
```

over HTTPS with `Content-Type: application/json`, status 200, no
redirect. Cloudflare / nginx config:

```nginx
location = /.well-known/assetlinks.json {
    default_type application/json;
    alias /var/www/.well-known/assetlinks.json;
    add_header Cache-Control "public, max-age=300";
}
```

If you serve the marketing site from the Flutter web build, drop the
file into `frontend/web/.well-known/assetlinks.json` so it ships with
the next deploy.

## 4. Verify the install-time check

After installing a release/upload-signed build:

```bash
adb shell pm get-app-links com.tropia.tropia
```

Look for `tropia.vn: verified`. `none` or `legacy_failure` means the
file isn't reachable or the fingerprint doesn't match.

You can also force a re-verification:

```bash
adb shell pm verify-app-links --re-verify com.tropia.tropia
```

## 5. Update the OAuth callback (future migration)

Once App Links verify reliably, switch the Google OAuth deep-link from
the custom scheme to the verified HTTPS URL:

- Backend env: `GOOGLE_APP_DEEP_LINK=https://tropia.vn/auth/callback`
  (currently `tropia://auth/callback`).
- The mobile app already handles both scheme variants in
  `handleGoogleCallback` — no Dart change needed.

The custom-scheme filter stays as a fallback for users on older
Android versions or platforms (iOS Universal Links is a parallel
mechanism; configure it via `apple-app-site-association` if you ship
the iOS app).
