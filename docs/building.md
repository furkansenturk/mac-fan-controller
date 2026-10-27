# Building

## Requirements

- macOS 14 or later to run the app
- Xcode 26 or later to build it: the app icon is an Icon Composer document (`.icon`)

## Run the app

```sh
open FanController.xcodeproj
```

Select the **FanController** scheme and press ⌘R. Builds are signed to run locally by default, so you don't need an Apple Developer account to try the app.

From the command line:

```sh
xcodebuild -project FanController.xcodeproj -scheme FanController build
```

## Tests

All logic lives in the Swift package, so it is tested without Xcode's UI:

```sh
cd Packages/FanKit
swift test
```

`swift test` needs XCTest, which is installed with Xcode but not with the Command Line Tools alone. If you see `no such module 'XCTest'`, point the toolchain at Xcode:

```sh
sudo xcode-select -s /Applications/Xcode.app
```

## Code signing

The privileged helper only accepts connections from an app signed by the **same team**. Reading sensors works without signing, but fan control needs a team ID. A free Apple ID works:

1. In Xcode, open **Settings › Accounts** and add your Apple ID. Xcode creates a *Personal Team* and an *Apple Development* certificate.
2. Find your team ID, which is the `OU` field of the certificate:

   ```sh
   security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
   ```

3. Create your signing config and set `DEVELOPMENT_TEAM` to that value:

   ```sh
   cp Config/Signing.example.xcconfig Config/Signing.xcconfig
   ```

4. Build and run, choose **Manual** for a fan, and turn on Fan Controller in **System Settings › General › Login Items**.

`Config/Signing.xcconfig` is ignored by git, so your team ID never ends up in a commit.

### When fan control stops working after a rebuild

macOS binds a registered helper to the code signature it was registered with. If you register it with one signature (for example before adding your team ID) and then run a build with another, launchd kills the helper at launch. The crash report says `Launch Constraint Violation`, and Settings › Fan Control shows the connection as *Not responding*.

To fix it, open **Settings › Fan Control** and click **Reinstall**.

### Running from Xcode while another copy is open

Each copy of the app drives the fans with its own active profile, so two copies would fight. When you run from Xcode, the new copy asks any other running copy to quit.

## Releasing

Releases are made by [semantic-release](https://semantic-release.gitbook.io) in the `release` job of `.github/workflows/ci.yml`, on every push to `beta` or `main` once the tests, the build and Semgrep pass. Nothing is done by hand.

While the app is in beta, all work goes to `beta`, the default branch, through short-lived `feat/…`, `fix/…` or `chore/…` branches merged as a single commit. Each release from `beta` is a pre-release such as `1.0.0-beta.1`, built without a Developer ID, so macOS asks for confirmation the first time it's opened. `main` holds stable releases: it stays untouched until the app is signed and notarized, then `beta` is merged into it for `1.0.0`.

1. The version follows from the [Conventional Commits](https://www.conventionalcommits.org) since the last tag: `fix:` gives a patch release, `feat:` a minor one, and `feat!:` or a `BREAKING CHANGE:` footer a major one. Other types (`docs:`, `ci:`, `test:`, `refactor:`, `chore:`…) don't release. On `beta`, the pre-release number goes up instead until the version changes.

2. `Scripts/set-version.sh` writes the version to `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Config/Base.xcconfig`. The app and the helper both take their `CFBundleVersion` from it, and the app restarts an installed helper whose version differs from its own, so the helper is updated with every release.
3. `Scripts/build-release.sh` builds the app and zips it as `dist/FanController-<version>.zip`, with a `.sha256` checksum.
4. `CHANGELOG.md` and `Base.xcconfig` are committed back to the branch as `chore(release): <version> [skip ci]`, the commit is tagged `v<version>`, and a GitHub release is published with the notes, the zip and its checksum (marked as a pre-release from `beta`). GitHub adds the source code archives to every release.

The configuration is in `.releaserc.json`; the tools are pinned in `package.json` and `package-lock.json`. GitHub Actions pushes the release commit straight to `beta` and `main`, so their protection only blocks force pushes and deletion: requiring pull requests or status checks would reject that commit.

The `npm` package that semantic-release depends on bundles copies of `undici` and `ip-address` with known denial-of-service issues, which `npm audit` reports. They can't be updated from here, and they are never run: that `npm` is only used to publish to the npm registry, which this project doesn't do.

To try a release locally without publishing anything:

```sh
npm ci --ignore-scripts
Scripts/set-version.sh 0.0.1 && Scripts/build-release.sh   # then: git checkout Config/Base.xcconfig
```

### The released app is ad-hoc signed

Release builds are signed without a team, so anyone can download them without an Apple Developer Program membership. Such a build reads every sensor, but **can't control fans**: the helper only accepts an app signed by its own team (see [security.md](security.md)), and the app doesn't register it. Fan control needs a build from source, signed with your own Apple ID as described above.

Because the app isn't notarized, macOS blocks it the first time. Open it once, then choose **Open Anyway** in **System Settings › Privacy & Security**. Verify the download first:

```sh
shasum -a 256 -c FanController-<version>.zip.sha256
```

Signing releases with a Developer ID and notarizing them would remove both limits. It needs a paid membership; the build script and the release job are where the certificate and `notarytool` would be added. Sign every release with the same Developer ID and bundle IDs from then on: macOS ties the registered helper to that identity, and changing it makes launchd refuse to start the helper until it is reinstalled from Settings › Fan Control.

## Configuration files

| File | Applies to | Contains |
| --- | --- | --- |
| `Config/Base.xcconfig` | Project | Bundle ID prefix, versions, deployment target, shared build settings |
| `Config/App.xcconfig` | `FanController` | Product name, Info.plist keys |
| `Config/Helper.xcconfig` | `FanHelper` | Product name, embedded Info.plist |
| `Config/Signing.xcconfig` | Project (optional) | Your team ID, not committed |

To change the bundle ID, edit `BUNDLE_ID_PREFIX` in `Base.xcconfig`, and update `FanHelperConstants` and the launchd plist in `Helper/` to match.

## App icon

The icon is an Icon Composer document, `App/Resources/AppIcon.icon`: a background gradient and two vector layers (blades and hub) that macOS renders with Liquid Glass. Xcode also builds an `AppIcon.icns` from it for macOS 14 and 15. Open it in Icon Composer (inside Xcode) to adjust colors or effects, or regenerate the layers with:

```sh
Scripts/generate-icon-layers.py App/Resources/AppIcon.icon/Assets
```

The menu bar uses a one-color template version of the same fan, `Assets.xcassets/MenuBarIcon`. SF Symbols are not used for the app icon, because Apple's license doesn't allow them in app icons.

## Diagnostics

```sh
Scripts/dump-sensors.sh
```

Prints the model, the fans, every IOHID temperature sensor and every temperature key the SMC exposes. See [smc-keys.md](smc-keys.md).
