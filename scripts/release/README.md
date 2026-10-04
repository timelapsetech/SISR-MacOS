# macOS release builds (SwiftUI + signing + notarization)

This folder contains `macos-swift-build-sign-notarize.sh`, which:

1. Regenerates `SISR.xcodeproj` and builds a **universal** `SISR.app` (arm64 + x86_64).
2. **Codesigns** with a **Developer ID Application** identity (hardened runtime + `SISR/SISR.entitlements`).
3. **Submits** the app to Apple **notarization** via `notarytool` (App Store Connect API key).
4. **Staples** the ticket and writes `dist/SISR-native-<version>-macos-universal.zip` for distribution.

## One-time Apple setup

1. **Apple Developer Program** membership.
2. **Developer ID Application** certificate  
   Xcode → Settings → Accounts → Manage Certificates → Developer ID Application.  
   Export as `.p12` (remember the export password) for CI, or rely on your login keychain locally.
3. **App Store Connect API key** for notarization (recommended by Apple for automation)  
   [App Store Connect](https://appstoreconnect.apple.com/) → Users and Access → Integrations → **Keys** → generate an **App Manager** (or **Developer**) key.  
   Download the `.p8` file once; note **Key ID** and **Issuer ID** (UUID on the same page).

## GitHub repository secrets (tag releases)

Create these in **Settings → Secrets and variables → Actions**:

| Secret | Purpose |
|--------|---------|
| `MACOS_CERTIFICATE_BASE64` | Base64-encoded `.p12` (see below) |
| `MACOS_CERTIFICATE_PASSWORD` | Password for that `.p12` |
| `APPLE_ASC_API_KEY_P8_BASE64` | Base64-encoded contents of the `.p8` API key file |
| `APPLE_ASC_API_KEY_ID` | Key ID (10 characters) |
| `APPLE_ASC_ISSUER_ID` | Issuer UUID from App Store Connect |

Encode files for secrets:

```bash
base64 -i Certificate.p12 | pbcopy   # paste into MACOS_CERTIFICATE_BASE64
base64 -i AuthKey_XXXXXXXX.p8 | pbcopy
```

## Notarization wait time

Successful notarization usually finishes in **a few minutes**; Apple’s queue can occasionally stretch longer. To avoid burning GitHub Actions minutes on a long poll, the script defaults to **`NOTARY_WAIT_TIMEOUT=25m`** (`notarytool submit --wait --timeout`). That is usually enough in practice; if you see **timeouts on healthy builds**, raise it (e.g. `45m`) in the workflow `env` or when running locally.

The **Release (macOS)** job sets **`timeout-minutes: 90`** as a runner-level backstop.

If notarization fails or times out, the script exits before stapling; see `xcrun notarytool history` with the same API key flags.

## Publishing a release

1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `scripts/generate_xcodeproj.py` (and `project.yml` / `SISRKit.version`), then regenerate the Xcode project.
2. Tag and push:

   ```bash
   git tag app-v1.0.4
   git push origin app-v1.0.4
   ```

3. Workflow **Release (macOS)** (`.github/workflows/release-macos.yml`) builds a universal `SISR.app`, signs, notarizes, and attaches `SISR-native-<version>-macos-universal.zip`.

You can also run **Actions → Release (macOS) → Run workflow** to produce an **unsigned** zip (no secrets) for debugging; it is available as a workflow artifact only, not attached to a release.

## Local build (your Mac)

With Developer ID already in your login keychain and API key on disk:

```bash
export APPLE_API_KEY_ID="XXXXXXXXXX"
export APPLE_API_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export APPLE_API_KEY_PATH="$HOME/private/AuthKey_XXX.p8"
./scripts/release/macos-swift-build-sign-notarize.sh
```

For a quick unsigned zip (no signing/notarization):

```bash
./scripts/release/macos-swift-build-sign-notarize.sh --skip-sign --skip-notarize
```

## Icon

Master art is `resources/icon-source.png`. Regenerate PNGs, AppIcon, docs logos, and `resources/icon.icns` with:

```bash
python3 resources/create_icon.py
```

(Requires macOS, Pillow, and Xcode command-line tools for `.icns`.)

## Troubleshooting

- **codesign / notary failures**: Open the log on the failing step; `notarytool log --uuid ...` for detail.
- **Hardened runtime**: If Apple rejects the bundle, adjust `SISR/SISR.entitlements` carefully and document why.
