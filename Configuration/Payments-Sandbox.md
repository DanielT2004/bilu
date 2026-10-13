# Build Bilu against the isolated payments sandbox

The normal Debug/Release configuration still uses production Supabase (`yysxjtexwlnvoptxcxlp`) and the source `Info.plist` keeps commerce and Pro disabled. Sandbox overrides are accepted only when compiling **Debug** with `BILU_PAYMENT_SANDBOX`. Missing or invalid sandbox configuration stops authentication locally; it never falls back to production.

The isolated payments project is `stddielncxelpqangfyk`. Its public-only configuration is supplied separately, for example `/tmp/bilu-payment-sandbox-public.json`:

```json
{
  "project_ref": "stddielncxelpqangfyk",
  "supabase_url": "https://stddielncxelpqangfyk.supabase.co",
  "supabase_anon_key": "<public anon or publishable key>"
}
```

The file may also contain the public deployment metadata `apple_environment: "Sandbox"`, `commerce_enabled`, and `pro_enabled: false`. The script refuses production URLs, non-Supabase endpoints, credentials in URLs, service-role/secret keys, and mismatched anon JWT project references. Anon/publishable keys are public client identifiers; Apple `.p8`, Supabase service-role keys, management tokens, and database passwords never belong in this file or the app.

From the repository root, create an unsigned simulator build:

```sh
python3 scripts/build_payment_sandbox.py \
  --config /tmp/bilu-payment-sandbox-public.json
```

The output is `/tmp/bilu-payments-sandbox/Build/Products/Debug-iphonesimulator/bilu.app`. Generated build-only settings live under `/tmp/bilu-payments-sandbox/SandboxConfiguration/`; neither `bilu/Info.plist` nor the Xcode project is rewritten. Use `--prepare-only` to inspect these files without building. The generated xcconfig preserves the share extension's own plist and bundle identifier.

For an existing registered physical device and signing setup:

```sh
python3 scripts/build_payment_sandbox.py \
  --config /tmp/bilu-payment-sandbox-public.json \
  --derived-data /tmp/bilu-payments-sandbox-device \
  --destination 'id=<device identifier>' \
  --signed
```

This uses the project's existing signing configuration; it does not change provisioning or install/launch the app. The bundle identifier remains `com.simonsoloman.bilu`, so this build replaces the production build on that device. Saved places remain on-device. Production Supabase sessions stay in the original Keychain item; each sandbox project uses a distinct service suffix. Purchase receipts and pending approval reminders similarly use `Commerce/Sandbox/<project-ref>/` while production retains `Commerce/PendingPurchases.json`.

The sandbox app manifest enables commerce and forces Pro off. The backend's independent commerce flag must also be enabled before any product is offered. The script refuses a scheme containing an Xcode `.storekit` configuration: this build must load the real App Store product `com.simonsoloman.bilu.discovery_pass` and use Apple's sandbox transactions. Configure the device's Sandbox Apple Account and the isolated server's Apple verification before making a test purchase. Do not use a production App Store account as purchase verification.

Local checks:

```sh
python3 scripts/test_payment_sandbox_build.py
xcodebuild test -project bilu.xcodeproj -scheme bilu \
  -destination 'platform=iOS Simulator,id=<installed simulator identifier>' \
  -only-testing:biluTests/SandboxConfigurationTests \
  -only-testing:biluTests/AccountSessionTests \
  -only-testing:biluTests/PurchaseStoreTests \
  CODE_SIGNING_ALLOWED=NO
```

These checks use test transports and isolated Keychain names. They do not prove Apple sign-in, product availability, real sandbox payment delivery, or deployed provider configuration. Those remain separate end-to-end checks.
