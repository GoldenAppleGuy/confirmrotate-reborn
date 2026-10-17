# ConfirmRotate Reborn

Asks before the screen rotates. Turn the phone and a button appears, upright for the way you are now holding it; tap it and the screen rotates. A modern take on the old ConfirmRotate tweak, rebuilt for iOS 15 to 17.

## Features

- **Confirm button**: appears beside the volume buttons when the phone is turned, showing the rotation lock symbol and "Rotate?". Haptic feedback on tap (can be turned off).
- **Only when it can rotate**: no button for apps that don't support the new orientation, or on the home and lock screens.
- **Auto-rotate** (optional): a ring fills around the button and the screen rotates by itself after a set delay. With Tap to Cancel, the button reads "Cancel?" and a tap keeps the screen as it is; turning back always cancels.
- **Gestures**: long press the button to rotate and add the app to the blacklist; swipe it away to dismiss it.
- **Portrait on app switch** (optional): apps open in portrait, decided before they appear (no visible turn). After any app switch, if the phone is held differently from how the app is shown, the button is offered again.
- **Whitelist / blacklist**: limit the tweak to some apps, or let some apps rotate freely. The settings show how many apps each list holds, and the lists keep selected apps at the top.
- **Always show in**: for apps such as YouTube that handle rotation themselves while declaring portrait only.
- **Timing**: how long the phone has to stay turned before the button appears (0 to 3 seconds), and how long it stays.
- **Appearance**: circle or rounded square, light or dark (or following the system), icon color, size, opacity and position.
- **Control Center toggle** (needs CCSupport): turn the tweak on and off. Its own icon (a phone with a rotate arrow, teal when on), so it isn't mistaken for the system rotation lock.
- **Translations**: German, Spanish, French, Italian, Japanese, Korean, Dutch, Portuguese (Brazil), Russian, Chinese (Simplified and Traditional), Turkish and Polish.
- The system rotation lock still wins: while it is on, nothing changes.

## Requirements

- iOS 15 to 18, jailbroken (rootless, roothide or rootful). Tested on iOS 17.0 (iPhone 15, Dopamine) and iOS 15.4.1 (iPhone 12 mini, Dopamine); iOS 16.1, 18.0 and 18.6 in the simulator only. roothide is untested.
- PreferenceLoader and AltList. CCSupport for the Control Center toggle.

The tweak picks its hooks at startup: iOS 17's traits pipeline (also used on iOS 18), iOS 16's earlier version of it, or the older path that iOS 15 uses (see How it works).

## Building

Needs [Theos](https://theos.dev). `./build.sh` builds all three packages into `packages/`:

- `*_iphoneos-arm64.deb`: rootless
- `*_iphoneos-arm64e.deb`: roothide (needs [roothide's Theos](https://github.com/roothide/theos), at `~/theos-roothide` or `$THEOS_ROOTHIDE`)
- `*_iphoneos-arm.deb`: rootful

Or one at a time: `make package` (rootless), `make package THEOS=<roothide Theos> THEOS_PACKAGE_SCHEME=roothide` (roothide) or `make package THEOS_PACKAGE_SCHEME=` (rootful).

### Testing in the simulator

`make SIM=1` builds the tweak alone for the iOS Simulator (x86_64, hooks through the ObjC runtime, no Substrate). Load it into a simulator's SpringBoard the way simject does:

```
xcrun simctl spawn <device> launchctl setenv DYLD_INSERT_LIBRARIES <path>/ConfirmRotateReborn.dylib
xcrun simctl spawn <device> launchctl stop com.apple.SpringBoard
```

It only acts in SpringBoard and logs to `/tmp/ConfirmRotateReborn/`. Turn the simulator with Device > Rotate Left/Right. iOS 18 simulators leave the pipeline's orientation events off; in this build, Record Rotation Test (`notifyutil -p com.goldenappleguy.confirmrotatereborn/rotationtest`) switches them on and records for 10 minutes.

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

iOS 18 works the same way. iOS 16 has an earlier version of the pipeline whose inputs don't carry the device orientation: a turn reaches `-[SBTraitsEmbeddedDisplayPipelineManager accelerometer:didChangeDeviceOrientation:]` and goes straight on to SpringBoard's orientation update. While holding, the tweak passes the held orientation on instead; confirming calls it with the new one.

iOS 15 has no such pipeline: every orientation change reaches SpringBoard through `-[SpringBoard _deviceOrientationChanged:]`. While holding, the tweak lets only the held orientation through it, and confirming passes the new orientation through it. Physical orientation changes still arrive there while holding (the system's own lock overrides stop them, so those can't be used). App switches come from `-[SBLayoutStateTransitionCoordinator beginTransitionForWorkspaceTransaction:]`. On iOS 15, switching back to an app can occasionally be slow to accept touches for about a second with the tweak enabled; it was left as it is.

## Diagnostics

The Diagnostics section in settings:

- **Status**: Active, Off, Paused, Unsupported (no known way to hook this iOS version) or Not Running.
- **Detailed Logging**: logs every turn, button and app switch, not just startup and errors.
- **Record Rotation Test**: for 30 seconds, logs what SpringBoard itself does while the phone is turned, and whether the pipeline is receiving turns.
- **Share Log**: a report for bug reports with the log, settings, device, iOS version, jailbreak type and support packages (not the list of installed tweaks), plus the latest SpringBoard crash report and a one-time survey of SpringBoard's rotation classes.
- **Try Again**: shown when the crash guard has paused the tweak.

Crash guard: if SpringBoard restarts twice in a row within 30 seconds of the tweak loading, the tweak pauses itself on the next start instead of hooking anything, so it can't cause a respring loop. Try Again clears it.

Files are in `/var/mobile/Documents/ConfirmRotateReborn/`.

## Settings

Stored in the `com.goldenappleguy.confirmrotatereborn` domain.

## License

MIT. See [LICENSE](LICENSE).
