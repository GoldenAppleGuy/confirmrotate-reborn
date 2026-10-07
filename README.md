# ConfirmRotate Reborn

Asks before the screen rotates. Turn the phone and a button appears, upright for the way you are now holding it; tap it and the screen rotates. A modern take on the old ConfirmRotate tweak, rebuilt for iOS 15 to 17.

## Features

- **Confirm button**: appears beside the volume buttons when the phone is turned, showing the rotation lock symbol and "Rotate?". Haptic feedback on tap (can be turned off).
- **Only when it can rotate**: no button for apps that don't support the new orientation, or on the home and lock screens.
- **Auto-rotate** (optional): a ring fills around the button and the screen rotates by itself after a set delay. With Tap to Cancel, the button reads "Cancel?" and a tap keeps the screen as it is; turning back always cancels.
- **Gestures**: long press the button to rotate and add the app to the blacklist; swipe it away to dismiss it.
- **Portrait on app switch** (optional): apps open in portrait, decided before they appear (no visible turn).
- **Whitelist / blacklist**: limit the tweak to some apps, or let some apps rotate freely. The settings show how many apps each list holds, and the lists keep selected apps at the top.
- **Always show in**: for apps such as YouTube that handle rotation themselves while declaring portrait only.
- **Appearance**: circle or rounded square, icon color, size, opacity, position and hide delay.
- **Control Center toggle** (needs CCSupport): turn the tweak on and off. Its own icon (a phone with a rotate arrow, teal when on), so it isn't mistaken for the system rotation lock.
- **Translations**: German, Spanish, French, Italian, Japanese, Korean, Dutch, Portuguese (Brazil), Russian, Chinese (Simplified and Traditional), Turkish and Polish.
- The system rotation lock still wins: while it is on, nothing changes.

## Requirements

- iOS 15 to 17, jailbroken (rootless or rootful). Tested on iOS 17.0 (iPhone 15, Dopamine) and iOS 15.4.1 (iPhone 12 mini, Dopamine). iOS 16 is untested.
- PreferenceLoader and AltList. CCSupport for the Control Center toggle.
- roothide: use the rootless package with roothide's patcher.

The tweak picks its hooks at startup: iOS 17's traits pipeline, or the older path that iOS 15 uses (see How it works).

## Building

Needs [Theos](https://theos.dev). `./build.sh` builds both packages into `packages/`:

- `*_iphoneos-arm64.deb`: rootless
- `*_iphoneos-arm.deb`: rootful

Or one at a time: `make package` (rootless) or `make package THEOS_PACKAGE_SCHEME=` (rootful).

## Publishing

Released through the [GoldenAppleGuy repo](https://goldenappleguy.github.io/repo/) ([GoldenAppleGuy/repo](https://github.com/GoldenAppleGuy/repo)). To publish a new version:

1. Raise `Version` in `control` and add it to the changelog in `tools/depiction.json`; commit.
2. `./build.sh` (both packages into `packages/`).
3. `python3 tools/update_repo.py <checkout of GoldenAppleGuy/repo>`, then commit and push that checkout.
4. Tag and release here with the packages attached: `git tag -a vX.Y.Z -m "ConfirmRotate Reborn X.Y.Z" && git push origin vX.Y.Z`, then `gh release create vX.Y.Z --verify-tag --title "ConfirmRotate Reborn X.Y.Z" --notes "..." packages/*.deb`.

Every version is on the [releases page](https://github.com/GoldenAppleGuy/confirmrotate-reborn/releases) with both packages.

## Layout

| Path | What |
| --- | --- |
| `Tweak.x` | The SpringBoard tweak |
| `prefs/` | Settings page (PreferenceLoader bundle, loads AltList for the app lists) |
| `ccmodule/` | Control Center toggle (CCSupport bundle) |
| `prefs/Localization/generate.py` | Translations: writes each language's `Root.strings` (settings) and `Tweak.strings` (button); run after changing any text |
| `layout/` | PreferenceLoader entry |
| `tools/update_repo.py`, `tools/depiction.json` | Publishing to the package repo, and its Sileo package page |

## How it works

On iOS 17, SpringBoard decides orientation in its traits pipeline, which reads the device orientation from `-[SBTraitsEmbeddedDisplayPipelineManager inputs]`. The tweak replaces that orientation with a held one, so turning the phone changes nothing. Confirming moves the hold to the new orientation and asks the pipeline to run again (`_noteInputsNeedUpdateAnimated:reason:`). The physical orientation is read from the same inputs, since `UIDevice` in SpringBoard follows the held orientation. App switches are handled in `layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:`, before the new app is laid out.

iOS 15 has no such pipeline: every orientation change reaches SpringBoard through `-[SpringBoard _deviceOrientationChanged:]`. While holding, the tweak lets only the held orientation through it, and confirming passes the new orientation through it. Physical orientation changes still arrive there while holding (the system's own lock overrides stop them, so those can't be used). App switches come from `-[SBLayoutStateTransitionCoordinator beginTransitionForWorkspaceTransaction:]`. On iOS 15, switching back to an app can occasionally be slow to accept touches for about a second with the tweak enabled; it was left as it is.

## Debugging

Create `/var/mobile/Documents/confirmrotate.debug` on the device and respring; the tweak then logs to `/var/mobile/Documents/confirmrotate.log`.

## Settings

Stored in the `com.goldenappleguy.confirmrotatereborn` domain.

## License

MIT. See [LICENSE](LICENSE).
