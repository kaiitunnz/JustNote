# Releasing JustNote locally

The app is built and installed on your own Mac. It is signed with a free **Apple Development** certificate, enough to run locally but not notarized for distribution.

## One-time signing setup

Sign in to a free Apple ID in Xcode -> Settings -> Accounts, which issues an "Apple Development" certificate. `project.yml` pins the Release configuration to that identity via `DEVELOPMENT_TEAM`; Debug stays unsigned. Confirm the certificate exists:

```sh
security find-identity -v -p codesigning
```

## Build and install

```sh
scripts/release.sh
```

This regenerates the project, builds a signed Release, quits a running JustNote instance, verifies the staged app bundle, and replaces `/Applications/JustNote.app`.

## Updating

Re-run `scripts/release.sh`.

## Limitations

- Not notarized, so the build is intended for this Mac.
- Requires macOS 27+.
