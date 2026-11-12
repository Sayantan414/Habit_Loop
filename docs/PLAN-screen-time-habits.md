# Plan: Screen-time habits (replacing the reels counter)

## Goal

Let the user add a **Quit habit that tracks itself from app usage time**, e.g.
"Instagram + YouTube under 45 min a day". Any day over the limit becomes a slip
automatically, exactly like reels habits do today. Then remove the reels
counter and its accessibility service, which is inaccurate (Facebook) and makes
banking/payment apps refuse to open.

Data comes from Android's `UsageStatsManager` with the **Usage access**
permission (`PACKAGE_USAGE_STATS`). This is not an accessibility permission,
so banking apps are not affected. Android only; the feature hides itself on
other platforms.

## Status (2026-11-12)

| Phase | State |
| --- | --- |
| 1. Native usage bridge | Done (`UsageChannel.kt`) |
| 2. Dart service + model | Done (`usage_service.dart`, Habit fields 16–17) |
| 3. Auto slips | Done (`core/screen_time.dart`, `syncScreenTimeHabits`) |
| 4. UI | Done (add-habit card, app picker, Today card, detail week view) |
| 5. Remove reels counter | Done; reels habits convert to manual Quit habits; assistant reports screen time |
| 6. Polish | README updated. **Not yet done:** testing on a real phone, including the midnight split |

Everything is verified with `flutter analyze`, `flutter test` and a debug
APK build only. Nothing has run on a device yet.

## What already exists and can be reused

| Piece | Where | Reuse |
| --- | --- | --- |
| Self-tracking Quit habit (`reelsTarget`, auto slips) | `lib/data/models/habit.dart`, `HabitsNotifier.syncReelsHabits()` in `lib/core/providers.dart` | Same pattern: read per-day totals, add/remove slips |
| Native bridge pattern | `ReelsChannel.kt` + `lib/core/services/reels_service.dart` | Copy the shape for a new `habitloop/usage` channel |
| Sync on app resume / new day | `refreshReminders()` in `providers.dart`, `app.dart:63` | Call the new sync from the same places |
| "Track automatically" option in the Quit form | `lib/features/add_habit/add_habit_screen.dart` | Swap reels target for app picker + minutes |
| Assistant knows habit types | `lib/features/assistant/assistant_tools.dart` | Rename type `reels` to `screen_time` |

## Before starting

- [ ] Commit the current uncommitted work (assistant feature, Gemini client
      changes). Start this feature on its own branch, e.g. `feature/screen-time-habits`.

## Phase 1: Native usage bridge (Kotlin)

**Learn first:** `UsageStatsManager.queryEvents()` vs `queryUsageStats()`;
`ACTIVITY_RESUMED` / `ACTIVITY_PAUSED` events; `AppOpsManager` permission
check; Flutter `MethodChannel`.

- [ ] Add to `AndroidManifest.xml`:
      `<uses-permission android:name="android.permission.PACKAGE_USAGE_STATS" tools:ignore="ProtectedPermissions" />`
      (add `xmlns:tools` to `<manifest>`).
- [ ] New `UsageChannel.kt` on channel `habitloop/usage`, registered in `MainActivity.kt`:
    - `hasPermission` → `AppOpsManager.unsafeCheckOpNoThrow(OPSTR_GET_USAGE_STATS, …) == MODE_ALLOWED`
    - `openSettings` → `Settings.ACTION_USAGE_ACCESS_SETTINGS`
    - `installedApps` → launchable apps (package, label), excluding Habit Loop itself
    - `dailyUsage(packages, days)` → `{ 'yyyy-MM-dd': { package: minutes } }`
- [ ] Compute foreground time from `queryEvents()`: pair each RESUMED with the
      next PAUSED/STOPPED of the same package, split sessions that cross
      midnight, and count a still-open session up to "now".
- [ ] Add a launcher-intent `<queries>` entry so `installedApps` can see apps
      on Android 11+.

**Done when:** a debug call from Dart prints today's minutes per app and they
match Digital Wellbeing within about a minute.

## Phase 2: Dart service + model

**Learn first:** Hive field rules (never reuse a field number; `defaultValue`
for new fields), `build_runner`.

- [ ] `lib/core/services/usage_service.dart`: thin wrapper over the channel,
      no-ops off Android (same style as `ReelsService`).
- [ ] `Habit` gets two fields:
    - `@HiveField(16) int? screenTimeLimit` (minutes per day)
    - `@HiveField(17, defaultValue: []) List<String> screenTimeApps` (package names)
    - getter `isScreenTimeHabit => isBad && screenTimeLimit != null`
    - add both to `toJson` / `fromJson` so backups keep them
- [ ] Re-run `dart run build_runner build` to regenerate `habit.g.dart`.

**Done when:** a screen-time habit can be saved, restarted, exported and
re-imported without losing its apps or limit.

## Phase 3: Auto slips

- [ ] `HabitsNotifier.syncScreenTimeHabits()`, modelled on `syncReelsHabits()`:
      for each running screen-time habit, sum minutes of its apps per day;
      over limit → slip, back under → no slip.
- [ ] History window: usage events are only kept by Android for roughly the
      last 7–10 days, so only sync days inside that window; older days keep
      whatever slips were already recorded.
- [ ] Call it from `refreshReminders()`, after `addHabit`/`updateHabit` of a
      screen-time habit, and on app resume (`app.dart`).
- [ ] Today counts live: today becomes a slip as soon as the limit is passed.

**Done when:** using Instagram past the limit, then reopening Habit Loop,
shows today as a slip; yesterday's slip state is unchanged after a restart.

## Phase 4: UI

**Learn first:** nothing new; follow `docs/DESIGN_SYSTEM.md`.

- [ ] Add-habit screen (Quit mode): "Track screen time automatically" switch →
      app picker (search + icons) and a daily limit in minutes
      (presets 15 / 30 / 45 / 60 + custom). Generated title, e.g.
      "Instagram + YouTube under 45 min".
- [ ] If Usage access is off: explain why it is needed, button to open
      settings, re-check on return.
- [ ] Habit card: progress ring "32 / 45 min" for today; turns warning colour
      near the limit and slip colour over it.
- [ ] Habit detail: last 7 days of minutes per day as a small bar list.
- [ ] Reminder notification text: "Stay under 45 min on Instagram + YouTube today."

**Done when:** the full flow (grant permission → create habit → see live
minutes on the card) works on a real phone in light and dark mode.

## Phase 5: Remove the reels counter

- [ ] Delete `ReelsCounterService.kt`, `ReelsStore.kt`, `ReelsChannel.kt`,
      `ReelsNotifications.kt`, `DoomscrollReminder.kt`,
      `res/xml/reels_accessibility_config.xml`, the `<service>` and reels
      `<queries>` entries in the manifest, and `reels_service_label`.
- [ ] Delete `lib/features/reels/`, `reels_service.dart`, `reelsProvider`,
      `ReelsState`, and the "Reels counter" tile in Settings.
- [ ] Existing reels habits: convert them to plain manual Quit habits (set
      `reelsTarget = null`, keep their slips). Keep `@HiveField(15) reelsTarget`
      in the model as deprecated; never reuse field 15.
- [ ] Assistant (`assistant_tools.dart`): habit type `reels` → `screen_time`;
      `report` enum `reels` → `screen_time`; drop the `doomscroll_reminder`
      setting; never let the assistant log slips on screen-time habits.
- [ ] Update tests in `test/` that mention reels.

**Done when:** no accessibility service appears in Android settings for Habit
Loop, banking apps open normally, and `flutter analyze` and `flutter test` pass.

## Phase 6: Polish and ship

- [ ] Update `README.md` (it still lacks the AI assistant, voice, widget,
      and this feature).
- [ ] Test on a real device across midnight (a session spanning 23:50–00:10
      is split between two days).
- [ ] Optional later: a WorkManager job every 15 minutes that notifies when a
      limit is crossed while Habit Loop is closed.

## Decisions

1. Existing reels habits: **convert** to manual Quit habits, keeping their slips (Phase 5).
2. Live "limit crossed" notification while the app is closed: **later**, not
   part of this feature (the optional Phase 6 item stays out of scope).
3. App picker: **every installed launchable app**, with search (Phase 1 `installedApps`, Phase 4 picker).
