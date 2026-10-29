# Contributing

Use small changes with a concrete behavior and appropriate tests. Run `go test -race ./...` and `go vet ./...`; mobile changes should also pass `flutter analyze` and `flutter test` from `mobile/`, plus the relevant platform build. Keep the shared protocol specification, JSON schema, Go and Flutter code consistent.

Do not silently advertise stub features. Add a capability only when a usable implementation exists and its host permission has been granted. Keep plugins explicit and local; arbitrary shell commands and downloadable code are outside this slice.

Useful next contributions: real Windows/Linux input backends, automated Android-to-Go instrumentation, per-device permission grants and revocation, mDNS discovery that never substitutes for identity verification, lifecycle/reconnection UX and accessible touchpad controls. Discuss incompatible protocol changes before implementation. Submit PRs once a public repository is selected.
