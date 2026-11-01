# Contributing

Open issues and pull requests in [shirishkoirala/linkpad](https://github.com/shirishkoirala/linkpad). Keep changes focused on a concrete behavior, with tests appropriate to the risk.

## Checks

From the repository root:

```sh
go test -race ./...
go vet ./...
python3 mobile/tool/test_package_windows.py
```

For shared Flutter changes, from `mobile/`:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --concurrency=1
```

Build affected platforms as well. See [PACKAGING.md](PACKAGING.md) for dependencies and [Windows input](docs/windows-input.md) for native and Docker test limits. A successful cross-build is not a substitute for native input testing.

## Compatibility and security

Keep the wire specification, JSON schema, Go server and Flutter clients consistent. Negotiate new capabilities so older peers remain usable. Advertise input only when a working backend and the necessary desktop permissions are available.

Preserve existing saved identities and computer migrations. Never commit pairing state, private keys, signing credentials or real pairing codes. Discovery must not substitute for certificate verification. Discuss incompatible protocol or storage changes before implementation.

Current follow-up work includes signed desktop distribution, physical installer/tray/startup checks, Wayland support, certificate renewal and finer per-device permissions. Windows/Linux input, nearby discovery and live device revocation already exist.

Report vulnerabilities privately using the contact in [SECURITY.md](SECURITY.md).
