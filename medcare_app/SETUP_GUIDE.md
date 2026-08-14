# MedCare Flutter App — Setup & File Guide

No voice/TTS/STT in this pass — this is the core app: live Firebase data,
all 5 tabs + Settings, matching your JSX prototype's UI and your
firmware's actual data shape.

---

## Step 0 — Your confirmed environment

- Flutter 3.35.5 (stable) / Dart 3.9.2
- JDK 17.0.12 LTS
- Android SDK 35, build-tools 35.0.0, licenses accepted
- VS Code + Flutter extension 3.138.0

All compatible with the versions in `pubspec.yaml` below — no changes
needed. The one consequence: Flutter 3.35.5 scaffolds new Android
projects with **Kotlin DSL** Gradle files, not the older Groovy style —
Step 3 below gives you that exact syntax.

---

## Step 1 — Create the project shell

```bash
flutter create medcare_app
cd medcare_app
```

Then **delete** the `lib/` and `pubspec.yaml` that `flutter create`
generated, and replace them with the ones in the file bundle I gave you
— copy the whole `lib/` folder and `pubspec.yaml` into your new project,
keeping the folder structure exactly as-is:

```
medcare_app/
  lib/
    main.dart
    app_root.dart
    theme/app_colors.dart
    models/  (slot, schedule_entry, device_status, caregiver, device_settings)
    services/firebase_service.dart
    state/app_state.dart
    widgets/ (status_dot, theme_reveal, tray_painter, medicine_card)
    screens/ (dashboard, tray, schedule, slot_editor, history, caregiver, settings)
  pubspec.yaml
```

Open the folder in VS Code (`code medcare_app`), install the **Flutter**
and **Dart** extensions if you haven't already.

```bash
flutter pub get
```

---

## Step 2 — Wire up Firebase (the one manual step)

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

- When it asks which Firebase project, pick **the exact same project
  your ESP32 firmware is already using** (`medcare-iot` per your
  `FIREBASE_DB_URL`) — not a new one.
- Select **Android** as a platform.
- This generates `lib/firebase_options.dart` automatically — `main.dart`
  already imports it, so don't hand-write that file yourself.

If `flutterfire configure` also asks about `google-services.json` — let
it place that in `android/app/` for you.

---

## Step 3 — Android/Gradle settings

Your `flutter --version` (3.35.5) confirms `flutter create` will scaffold
**Kotlin DSL** Gradle files (`build.gradle.kts` / `settings.gradle.kts`),
not the older Groovy style — so here's the exact syntax you'll actually
see, not a "check which you have" hedge.

**Good news first:** `flutterfire configure` (Step 2) usually inserts the
`google-services` plugin lines into these files for you automatically on
current `flutterfire_cli` versions. Run Step 2 first, then just verify
against what's below rather than hand-editing blind.

`android/settings.gradle.kts` — the `plugins { }` block should include:
```kotlin
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.7.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}
```

`android/app/build.gradle.kts` — top-of-file `plugins { }` block:
```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}
```

Same file, inside `android { defaultConfig { } }` — note Kotlin DSL uses
`=` assignment, not the Groovy `minSdkVersion 23` style:
```kotlin
android {
    namespace = "com.yourname.medcare_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.yourname.medcare_app"
        minSdk = 23          // override Flutter's default — Firebase needs 23+
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
}
```

If `flutterfire configure` already added the `google-services` plugin
lines and they look different from above (e.g. a different AGP/Kotlin
version number), **leave its version numbers as-is** — those are the
ones actually compatible with your installed Android SDK 35 / build-tools
35.0.0, and mine above are just an illustration of the shape, not a
mandate to match exactly.

---

## Step 4 — minSdk choice (for "runs smoothly on most Android phones")

`minSdkVersion 23` (Android 6.0+) covers effectively all active Android
devices today and is the floor Firebase's current SDKs require — you
can't realistically go lower without downgrading Firebase packages. This
is already set in the snippet above.

For actual smoothness (not just installability):
- The app uses `IndexedStack` for tabs (keeps all 5 screens alive, no
  rebuild-on-switch jank) — already done in `app_root.dart`.
- No heavy image assets yet, so first-run size/load time is small.
- `CustomPainter` for the tray is cheap — 5 arcs, redrawn only when
  `slots`/`activeSlot` actually change (see `shouldRepaint` in
  `tray_painter.dart`).

---

## Step 5 — Run it

```bash
flutter devices        # confirm your phone/emulator shows up
flutter run
```

If you're testing on a **physical phone** over USB, make sure USB
debugging is enabled (Developer Options) and you accept the RSA key
prompt on the phone.

---

## What's fixed vs. what's flagged

**Fixed — the single-slot-update bug:**
`FirebaseService.pushSlot()` writes only
`/dispensers/{id}/slots/{index}`, never the whole `/slots` node.
`AppState.saveSlot()` replaces exactly one entry in the local list via
`List.of(slots)` + `next[index] = updated`, never rebuilding/resetting
the whole list. If you ever see the bug again, check for any code path
that calls `.set()` on the parent `/slots` reference with all 5 slots
at once — that's almost always the cause.

**Flagged, not built — needs a firmware-side addition:**
Tapping a slot in the Tray tab calls `dispenseSlot()`, which writes
`"dispense_slot_N"` to `/command`. **Your firmware's `streamCallback()`
only currently handles `"start_refill"` / `"exit_refill"`** — manual
single-slot dispense from the app won't do anything on the device until
you add a branch like:

```cpp
} else if (cmd.startsWith("dispense_slot_")) {
  int slot = cmd.substring(14).toInt();
  if (state == STATE_IDLE && slot >= 0 && slot < NUM_SLOTS) {
    beginDispense(slot, 0); // dispatches schedule index 0 for that slot
  }
}
```
right alongside the existing `start_refill`/`exit_refill` checks in
`streamCallback()`. Refill mode (`startRefill()`/`exitRefill()` in
`AppState`) **is** fully wired already since your firmware already
handles those two commands.

**Flagged — Settings and History have honest limitations right now:**
- Settings' Wi-Fi/password fields save locally only — firmware doesn't
  read config from Firebase yet (noted in the screen itself).
- History shows *today's* live schedule status, not a scrollable past
  log — your firmware pushes `/events` but nothing reads that list back
  yet (also noted in the file).

---

## Next steps, when you're ready

1. Test Dashboard/Tray/Schedule/History/Caregiver against your live
   Firebase data — confirm the slot-update fix by editing one slot and
   checking Firebase console shows only that slot's node changed.
2. Add the firmware snippet above if you want Tray taps to actually
   dispense.
3. Circle back to voice (TTS/STT) and audio — deliberately skipped this
   round per your request.
