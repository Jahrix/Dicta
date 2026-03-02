# Dicta Auto-Updates

Dicta uses Sparkle for in-app update checks and GitHub Actions for release publishing.

## Generate Sparkle keys locally

1. Download Sparkle tools:
   `bash scripts/sparkle_tools.sh 2.9.0 .sparkle-tools/2.9.0`
2. Generate keys:
   `.sparkle-tools/2.9.0/bin/generate_keys`
3. Copy the public key into `Dicta/Resources/Info.plist` under `SUPublicEDKey`.

## Configure GitHub secrets

Add this repository secret in GitHub Settings > Secrets and variables > Actions:

- `SPARKLE_EDDSA_PRIVATE_KEY`

The secret value should be the private EdDSA key output from Sparkle's `generate_keys` tool.

## Release flow

1. Ensure GitHub Pages is configured to use GitHub Actions as the source.
2. Create and push a version tag:
   `git tag vX.Y.Z`
   `git push origin vX.Y.Z`
3. The `release.yml` workflow will:
   - build `Dicta.app`
   - create `Dicta-vX.Y.Z.zip`
   - sign the zip with Sparkle
   - update `docs/appcast.xml`
   - deploy `docs/` to GitHub Pages
   - upload the zip to GitHub Releases

## Feed URL

Sparkle reads updates from:

`https://jahrix.github.io/Dicta/appcast.xml`

## Production signing note

This repository's release workflow disables code signing so CI can build without certificates. For production Sparkle updates, release builds should be signed and notarized with Developer ID credentials before distribution.
