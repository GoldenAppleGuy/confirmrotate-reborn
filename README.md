# ConfirmRotate Reborn

Asks before the screen rotates. Turn the phone and a button appears, upright for the way you are now holding it; tap it and the screen rotates. A modern take on the old ConfirmRotate tweak, rebuilt for iOS 17.

## Features

- **Confirm button**: appears beside the volume buttons when the phone is turned, showing the rotation lock symbol and "Rotate?". Haptic feedback on tap.
- **Only when it can rotate**: no button for apps that don't support the new orientation, or on the home and lock screens.
- **Auto-rotate** (optional): a ring fills around the button and the screen rotates by itself after a set delay. With Tap to Cancel, the button reads "Cancel?" and a tap keeps the screen as it is; turning back always cancels.
- **Gestures**: long press the button to rotate and add the app to the blacklist; swipe it away to dismiss it.
- **Portrait on app switch** (optional): apps open in portrait, decided before they appear (no visible turn).
- **Whitelist / blacklist**: limit the tweak to some apps, or let some apps rotate freely.
- **Always show in**: for apps such as YouTube that handle rotation themselves while declaring portrait only.
- **Appearance**: circle or rounded square, icon color, size, opacity, position and hide delay.
- **Control Center toggle** (needs CCSupport): turn the tweak on and off.
- The system rotation lock still wins: while it is on, nothing changes.

## Requirements

- iOS 17, jailbroken (rootless or rootful). Tested on iOS 17.0 (iPhone 15, Dopamine).
- PreferenceLoader and AltList. CCSupport for the Control Center toggle.
- roothide: use the rootless package with roothide's patcher.

The tweak hooks the traits pipeline that iOS 17 uses to decide orientation, so it does nothing on earlier versions; the package requires iOS 17.

## Building

Needs [Theos](https://theos.dev). `./build.sh` builds both packages into `packages/`:

- `*_iphoneos-arm64.deb`: rootless
- `*_iphoneos-arm.deb`: rootful

Or one at a time: `make package` (rootless) or `make package THEOS_PACKAGE_SCHEME=` (rootful).

## Layout

| Path | What |
| --- | --- |
| `Tweak.x` | The SpringBoard tweak |
| `prefs/` | Settings page (PreferenceLoader bundle, loads AltList for the app lists) |
| `ccmodule/` | Control Center toggle (CCSupport bundle) |
| `layout/` | PreferenceLoader entry |

## How it works

On iOS 17, SpringBoard decides orientation in its traits pipeline, which reads the device orientation from `-[SBTraitsEmbeddedDisplayPipelineManager inputs]`. The tweak replaces that orientation with a held one, so turning the phone changes nothing. Confirming moves the hold to the new orientation and asks the pipeline to run again (`_noteInputsNeedUpdateAnimated:reason:`). The physical orientation is read from the same inputs, since `UIDevice` in SpringBoard follows the held orientation. App switches are handled in `layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:`, before the new app is laid out.

## Debugging

Create `/var/mobile/Documents/confirmrotate.debug` on the device and respring; the tweak then logs to `/var/mobile/Documents/confirmrotate.log`.

## Settings

Stored in the `com.goldenappleguy.confirmrotatereborn` domain. Settings from the first test versions (`com.goldenappleguy.confirmrotate17`) are copied over once, and the package replaces that earlier package.
