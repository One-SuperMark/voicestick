# VoiceStick Release Process

## One-SuperMark fork: macOS ARM64 cloud package

For a user-facing desktop change, finish the local source review and set both `VERSION` and `desktop/macos/Sources/VoiceStickApp/Info.plist` to the same four-number version. Increase the fourth number once when committing the change; for example, `0.3.4.7.a` becomes `0.3.4.8`. Commit and push `main` without rebuilding, replacing, or launching the local app.

The `macOS ARM64 Package` workflow in `.github/workflows/macos-arm64.yml` runs when `main` receives a desktop/version/build-script change. It can also be started manually from the Actions tab. It checks the committed version, builds an ARM64-only app, packages a DMG and ZIP, verifies the app signature and DMG integrity, and uploads them as a 14-day Actions artifact. Check the run result and download the `VoiceStick-<version>-macOS-arm64-test` artifact from that run. A successful cloud build does not mean the downloaded app has been installed or launched on the user's Mac.

This fork workflow is a **test-package path**, not a public update feed: a clean GitHub runner without Apple credentials produces an ad-hoc signed, unnotarized package. Do not treat it as a Developer ID release or auto-update package. It does not change `firmware/version.txt`, build or upload StickS3 firmware, publish a GitHub Release, update the website, or touch the local `/Applications/VoiceStick.app`. Firmware versions are changed only when preparing a firmware flash/release, independently from desktop commits. Formal distribution requires a separate Developer ID signing, notarization, Sparkle signing, and fork-specific update-feed setup before publishing.

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

The fork's five-part debug version is not used for this upstream tag-based flow; its fork commit and cloud-package rules are described above. Linux CMake and Windows resource metadata consume the first four numeric components.

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
