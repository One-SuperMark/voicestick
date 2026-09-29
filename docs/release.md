# VoiceStick Release Process

## One-SuperMark fork: macOS ARM64 cloud package

For a user-facing desktop change, finish the local source review and set `VERSION`, `CFBundleShortVersionString`, and `CFBundleVersion` in `desktop/macos/Sources/VoiceStickApp/Info.plist` to the same three-number version. Increase the third number once when committing the change; the migration from the previous fork version `0.3.4.8` is `0.3.5`. The formal commit-and-push path uses static local checks and cloud packaging. Local development display revisions are separate from all three formal version fields.

The user's local acceptance requirement is separate: desktop changes must also be installed and launched on this Mac. Without authorization to commit, push, or publish, use `REQUIRE_DEVELOPER_ID=1 bash scripts/build-macos.sh --development` to create an optimized ARM64 working-tree app signed with the configured Developer ID. Each successful development build has a four-part display version such as `0.3.6.1`, `0.3.6.2`, and so on; a new formal baseline starts again at `.1`. The sequence is persisted only under ignored `build/` state, and the resulting app carries `VoiceStickDevelopmentVersion`. The source `VERSION` and both Apple bundle fields remain three-part; `--release` cloud packages do not carry this development metadata. Sparkle's display formatter and the settings window title show the development version, but updater comparisons and remote release versions remain unchanged. The removed current-version menu must not be restored.

If a formal release is authorized, prefer its verified artifact for installation. Quit the exact old executable before replacement, keep recoverable backups only under `build/local-app-backups/`, verify the installed executable hash against the new build, then launch and inspect the changed UI. Local development packages are not uploaded to the public update feed. This does not authorize a repository push or release, and local signing is not proof of Apple notarization or a real Sparkle version-to-version upgrade.

The `macOS ARM64 Package` workflow in `.github/workflows/macos-arm64.yml` runs when `main` receives a desktop/version/build-script change. It can also be started manually from the Actions tab. It checks the committed version, builds an ARM64-only app on a `macos-15` runner, packages a DMG and ZIP, verifies the app signature and DMG integrity, and uploads them as a 14-day Actions artifact. Check the run result and download the `VoiceStick-<version>-macOS-arm64-test` artifact from that run. A successful cloud build does not mean the downloaded app has been installed or launched on the user's Mac.

This fork workflow is a **test-package path**, not a public update feed: a clean GitHub runner without Apple credentials produces an ad-hoc signed, unnotarized package. Do not treat it as a Developer ID release or auto-update package. It does not change `firmware/version.txt`, build or upload StickS3 firmware, publish a GitHub Release, update the website, or touch the local `/Applications/VoiceStick.app`. Firmware versions are changed only when preparing a firmware flash/release, independently from desktop commits.

## One-SuperMark fork: signed macOS release

The separate `.github/workflows/macos-release.yml` starts from a `v<VERSION>` tag on this fork. It must fail if Developer ID signing, Apple notarization, or Sparkle signing is unavailable. After an ARM64 build, Developer ID verification, notarization, stapling, and DMG verification succeed, it signs the final DMG with the fork's Sparkle EdDSA key. It verifies that the private key matches the packaged app's public key, generates and signs `appcast.xml`, then publishes the DMG, appcast, and checksum to one GitHub Release. The firmware, upstream OSS, website, and local installed app remain outside this workflow. A successful GitHub Release is not evidence that the local app was upgraded or that an end-to-end in-app update works.

Before pushing the release tag, configure the fork's Actions secrets: `MACOS_CERTIFICATE_P12` (base64-encoded Developer ID certificate with private key), `MACOS_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `SPARKLE_PRIVATE_ED_KEY` (the fork's separate EdDSA seed). Restrict who can edit workflows and access repository settings because a workflow with these secrets can sign releases. Never commit these values, print them in logs, or store them in project knowledge. The release workflow validates that the tag exactly matches the three-part `VERSION`; create and push the tag only after the matching `main` commit is present and credentials are configured.

Write the actual user-facing Chinese changes and migration instructions in `docs/releases/<VERSION>.md` before committing. The formal workflow requires this nonempty version-specific file, embeds it as Markdown in the signed Sparkle appcast, and passes the same file to `gh release create --notes-file`. Do not fall back to generated template notes or replace concrete changes with a generic release heading. Sparkle 2.9 and the client's minimum macOS 12 support the embedded Markdown format.

The fork app reads `https://github.com/One-SuperMark/voicestick/releases/latest/download/appcast.xml`, not the upstream website. The appcast points to the versioned, notarized ARM64 DMG and is itself signed; Sparkle verifies both the feed and update before extraction. The workflow does not publish the test ZIP as an update. The already published `v0.3.5` app did not start Sparkle and cannot migrate automatically: manually install the first newer formal release with the updater, then verify a later version-to-version upgrade. Until that release is published, the fork feed URL has no `appcast.xml` asset and manual checks from an unpublished build will fail.

After a formal release, inspect the public `appcast.xml` and versioned DMG URLs, confirm the feed's version, ARM64 requirement, file length, and EdDSA signature, and test “检查更新…” from an installed older formal build. The workflow's signature checks prove package metadata, not the user's installation or restart.

The original multi-platform workflow `.github/workflows/release.yml` is restricted to `78/voicestick`. A `v<version>` tag in the One-SuperMark fork does not run its firmware/OSS publishing path.

## Original upstream multi-platform release flow

VoiceStick releases have three moving parts:

- macOS app: built, signed, notarized, and uploaded by GitHub Actions.
- StickS3 firmware: built by GitHub Actions and uploaded to Aliyun OSS and GitHub Releases.
- Windows app: built and signed manually on the Windows signing machine, then uploaded to the matching GitHub Release.

The Windows package is the special case because the signing certificate is local hardware or local machine state. The release process supports either order:

- Build and sign Windows first, then let GitHub Actions publish macOS and firmware.
- Publish macOS and firmware first, then build/sign Windows and upload it afterward.

In both cases, finish by redeploying the website and verifying all update URLs.

## Version Sources

Update both version files before creating the release tag:

```text
VERSION
firmware/version.txt
```

`VERSION` is used by the desktop packaging scripts and the GitHub release workflow. `firmware/version.txt` is the firmware version reported by the device, so it must match the release version for OTA update detection to work correctly.

The fork's desktop release version is now three-part. Linux CMake and Windows resource metadata consume the numeric components of `VERSION`, but the fork's macOS-only release does not package either platform.

For release `0.2.4`, the tag must be:

```text
v0.2.4
```

The GitHub Actions release workflow validates that `v<VERSION>` matches the pushed tag.

## Standard Flow

1. Update `VERSION` and `firmware/version.txt` to the new version.
2. Commit the version change and any release workflow changes.
3. Push `main`.
4. Push the release tag:

```sh
git tag -a v0.2.4 -m "VoiceStick 0.2.4"
git push origin main
git push origin v0.2.4
```

Pushing the tag runs `.github/workflows/release.yml`. That workflow builds:

- `VoiceStick-<version>.dmg`
- `VoiceStick-<version>.zip`
- `VoiceStick-<version>.signature`
- `voicestick-firmware-sticks3-ota-<version>.bin`
- `voicestick-firmware-sticks3-merged-<version>.bin`
- firmware checksums and `manifest.json`

It also uploads the firmware to Aliyun OSS under both:

```text
voicestick/firmwares/<version>/
voicestick/firmwares/latest/
```

After publishing the GitHub Release, the workflow requests a website deploy so the appcast is refreshed.

## Windows First

Use this flow when the Windows package has already been built and signed before the macOS/firmware release.

1. Set the new version in `VERSION`.
2. On the Windows signing machine, build and sign the MSI:

```bat
scripts\build-msi.bat
```

The output is:

```text
desktop\windows\build-msi-x64\VoiceStick_<version>.msi
```

3. Confirm `firmware/version.txt` also matches the new version.
4. Commit, push `main`, and push the matching `v<version>` tag.
5. Wait for the release workflow to finish successfully.
6. Upload the signed MSI to the same GitHub Release:

```sh
gh release upload v0.2.4 desktop/windows/build-msi-x64/VoiceStick_0.2.4.msi --repo 78/voicestick
```

7. Re-run the website deploy workflow so the appcast includes the Windows MSI:

```sh
gh workflow run deploy-website.yml --repo 78/voicestick --ref main
```

## macOS and Firmware First

Use this flow when macOS and firmware should be published before the Windows package is ready.

1. Update `VERSION` and `firmware/version.txt`.
2. Commit, push `main`, and push the matching `v<version>` tag.
3. Wait for the release workflow to publish macOS and firmware.
4. Later, on the Windows signing machine, build and sign the MSI:

```bat
scripts\build-msi.bat
```

5. Upload the signed MSI to the already published GitHub Release:

```sh
gh release upload v0.2.4 desktop/windows/build-msi-x64/VoiceStick_0.2.4.msi --repo 78/voicestick
```

6. Re-run the website deploy workflow:

```sh
gh workflow run deploy-website.yml --repo 78/voicestick --ref main
```

Until the MSI is uploaded and the website deploy has run, Windows clients will not see the new Windows update in the appcast.

## Verification

After every release, verify the appcast, firmware manifest, and actual package URLs.

Stable update endpoints:

```text
https://78.github.io/voicestick/appcast.xml
https://xiaozhi-voice-assistant.oss-cn-shenzhen.aliyuncs.com/voicestick/firmwares/latest/manifest.json
```

For version `0.2.4`, the appcast should contain:

```text
https://github.com/78/voicestick/releases/download/v0.2.4/VoiceStick_0.2.4.msi
https://github.com/78/voicestick/releases/download/v0.2.4/VoiceStick-0.2.4.zip
```

The firmware manifest should contain:

```text
https://xiaozhi-voice-assistant.oss-cn-shenzhen.aliyuncs.com/voicestick/firmwares/0.2.4/voicestick-firmware-sticks3-ota-0.2.4.bin
https://xiaozhi-voice-assistant.oss-cn-shenzhen.aliyuncs.com/voicestick/firmwares/0.2.4/voicestick-firmware-sticks3-merged-0.2.4.bin
```

Use `HEAD` requests or a browser to confirm every URL returns `200`.

```powershell
Invoke-WebRequest -UseBasicParsing https://78.github.io/voicestick/appcast.xml
Invoke-WebRequest -UseBasicParsing https://xiaozhi-voice-assistant.oss-cn-shenzhen.aliyuncs.com/voicestick/firmwares/latest/manifest.json

Invoke-WebRequest -UseBasicParsing -Method Head https://github.com/78/voicestick/releases/download/v0.2.4/VoiceStick_0.2.4.msi
Invoke-WebRequest -UseBasicParsing -Method Head https://github.com/78/voicestick/releases/download/v0.2.4/VoiceStick-0.2.4.zip
Invoke-WebRequest -UseBasicParsing -Method Head https://xiaozhi-voice-assistant.oss-cn-shenzhen.aliyuncs.com/voicestick/firmwares/0.2.4/voicestick-firmware-sticks3-ota-0.2.4.bin
Invoke-WebRequest -UseBasicParsing -Method Head https://xiaozhi-voice-assistant.oss-cn-shenzhen.aliyuncs.com/voicestick/firmwares/0.2.4/voicestick-firmware-sticks3-merged-0.2.4.bin
```

Also confirm these workflow runs are successful:

- `Release Build`
- `Deploy Website to GitHub Pages`

The release is complete when:

- macOS appcast entry points to the new Sparkle ZIP.
- Windows appcast entry points to the new signed MSI.
- firmware `latest/manifest.json` reports the new version.
- OTA and merged firmware URLs are reachable.
- the GitHub Release contains all macOS, Windows, and firmware assets.
