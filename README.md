# AirPosture

AirPosture is a menu-bar posture coach for Mac. It uses compatible AirPods to notice when your head stays off the Neutral Posture you set, then nudges you with a faint Glow, a sound, and a Sit up straight! banner.

There is no account and no Dock icon. Click the AirPosture icon at the top of the screen to open it.

## What you need

- A Mac running macOS 14 Sonoma or later
- Compatible headphones: AirPods Pro, AirPods Max, AirPods 3 / 4, or other Apple headphones with spatial audio head tracking. Original AirPods and AirPods 2 stay **Disconnected**.
- Permission for Motion & Fitness
- Optional: Notifications (for banners) and Focus Status (hides sit-up banners while Focus is on)

## Install and open

From the AirPosture folder in Terminal:

```bash
make run
```

That builds AirPosture and opens it.

To put it in Applications and open it from there:

```bash
make install
```

Always open the AirPosture app, not a loose program file from a build folder. The app is what macOS needs for Motion & Fitness.

AirPosture lives in the menu bar. Look at the top of the screen — not the Dock.

## First 5 minutes

1. Put on compatible AirPods and connect them to the Mac.
2. Open AirPosture. Look in the menu bar, not the Dock.
3. Allow Motion & Fitness when macOS asks. If you dismissed it: System Settings → Privacy & Security → Motion & Fitness.
4. Click the AirPosture icon in the menu bar.
5. Sit how you want to hold yourself, then click **Set Neutral Posture**. **Desk** is the default. Switch to **Sofa** and set Neutral Posture again if you want a second baseline.
6. Leave Tracking on. A faint **Glow** appears as you drift. If you stay off Neutral Posture for a few seconds, AirPosture plays **Pop** and shows a **Sit up straight!** banner.

Allow Notifications if you want that banner. Glow still works if you skip it.

## Using AirPosture

### The menu-bar icon

The icon turns orange while you are off Neutral Posture through the Grace Period, and red once a slouch is sustained. When headphones are missing it shows a gray AirPods symbol, and the badge may say **Disconnected**.

### The avatar and coach

The figure in the panel mirrors how you sit. The one-line coach says things like **Upright**, **Waiting for AirPods**, **Lift your chin**, or **Looking aside**.

### This week and History

**This week** shows a short upright / slouch / off-neutral summary. Click it to expand Monday–Sunday bars: green is time within your Sensitivity, orange is the Grace Period countdown, red is a sustained slouch, and gray is older off-neutral time that was not split that way.

**History** is in that same expanded area. Choose 7, 30, or 90 days (30 by default). Time is counted only while Tracking is on, headphones are Connected, and the active Desk or Sofa preset has a Neutral Posture.

### Desk and Sofa

Desk and Sofa keep two Neutral Postures. Switching applies that preset right away. If you have not set Neutral Posture for the one you picked, the figure and This week wait until you do.

### Options

Click **Options** to open Monitoring, Breaks, Reminders, Appearance, and Pause & feedback.

- **Monitoring** — Tracking is on by default. Sensitivity is how far you can drift. Grace Period is how long you can stay off Neutral Posture before a nudge. **Ignore slouch when I turn** is on by default, so looking aside does not count as a slouch. **Show head turn** rotates the figure; it does not change when AirPosture counts a slouch.
- **Breaks** — Break reminders stay off until you turn them on.
- **Reminders** — Warning style defaults to **Glow**. Early visual cue is on. Sound defaults to **Pop**. You can change fade-in, max strength, color, and volume here.
- **Appearance** — Icon style defaults to Posture figure. You can also pick Horizon cross or Minimal dot.
- **Pause & feedback** — Snooze, plus Sit-up chime (off by default).

### Break reminders

Break reminders are off until you turn them on. When they are on, a countdown appears in the menu bar and at the top of the panel. At zero, AirPosture plays your sound and one of these banners: **Time for a walk**, **Drink some water**, or **Rest your eyes**. Mix rotates those three — Mix is a setting, not a banner title.

Snooze and Focus skip that reminder. The next interval starts right away. Breaks never draw the slouch Glow and do not change This week.

### Snooze and Esc

Snooze hides Glow and mutes sound and banners. Tracking and This week keep running. Click **Resume** to clear snooze. Snooze is forgotten if you quit AirPosture.

Press **Esc** while a warning Glow (or other warning style) is on screen to snooze 15 minutes. macOS may ask for Input Monitoring so Esc still works while you type in another app.

### Quit

Click **Quit AirPosture** at the bottom of the panel.

## If something’s wrong

1. **Disconnected or Waiting for AirPods.** Put on compatible headphones and connect them to the Mac. Original AirPods and AirPods 2 stay Disconnected. The badge may say **Disconnected** or **Searching**; the coach says **Waiting for AirPods** until motion arrives.
2. **Set Neutral Posture is dimmed.** Turn Tracking on and wait until the badge says Connected. The button stays dim while headphones are missing or Tracking is off.
3. **Motion access is off.** Enable it in System Settings → Privacy & Security → Motion & Fitness. AirPosture shows that same path in the panel when access is denied.
4. **No Sit up straight! banner.** Allow Notifications. If Focus is on and you allowed Focus Status, AirPosture hides sit-up banners (Glow and sound still follow your settings). Snooze also mutes banners. The banner waits until you stay past Neutral Posture through the Grace Period — or twice that wait if **Wait for 2× grace before sound** is on.
5. **Glow feels late or too strong.** Shorten Grace Period or Fade-in if it feels late. Turn Early visual cue off if you only want Glow after the Grace Period. Lower Max strength, or choose Dim or Off, if it feels too strong. macOS Reduce Transparency turns Glow and Blur into Dim.

## Privacy

AirPosture works only on this Mac. There is no account and no network.

## Building from source

See [docs/developer.md](docs/developer.md).

Avatar adapted from Coolio 2.0 by [RabidTribble](https://blendswap.com/blend/27852) ([CC BY-NC-SA](https://creativecommons.org/licenses/by-nc-sa/4.0/)).
