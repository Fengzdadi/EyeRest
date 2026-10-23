# EyeRest

[![CI](https://github.com/Fengzdadi/EyeRest/actions/workflows/ci.yml/badge.svg)](https://github.com/Fengzdadi/EyeRest/actions/workflows/ci.yml)

A tiny macOS menu bar app for the **20-20-20 rule**: every 20 minutes, look at
something 20 feet (about 6 m) away for 20 seconds.

每 20 分钟提醒你看 6 米外的地方 20 秒。原生 Swift，无需任何权限。

## Features

- Full-screen break on every display, including over full-screen apps.
  Press **Esc** to skip, or postpone 5 minutes.
- **A long break every hour.** Every third break lasts 5 minutes and asks you
  to stand up and move. Being away for 5 minutes counts as one.
- **Heads-up first.** A small pill at the top of the screen counts down the
  last 10 seconds, with Start Now and +5 min buttons. It never takes keyboard
  focus, so you can keep typing.
- **Doesn't cut you off mid-sentence.** If you're typing when the break is due,
  it waits for a 2-second pause (at most 30 seconds). If it does start while
  you type, your keys keep going to your app until you pause.
- **Knows when you're away.** No input for 2 minutes, a locked screen or a
  sleeping Mac counts as a natural break and restarts the timer. Watching a
  video (an app keeping the display awake) doesn't count as away.
- **Doesn't interrupt you when you're busy.** A due break waits while:
  - the camera or microphone is in use (a call),
  - Keynote or PowerPoint is showing a slideshow,
  - a calendar meeting is in progress (optional, needs calendar access).

  When you're free again it gives you a minute before the break starts.
- Pause for 30 minutes, 1 hour or until you resume.
- Configurable interval (20/30/45/60 min), break length (20/30/60 s), long
  break frequency and length, and the sound at the end of a break.
- English and Simplified Chinese (界面支持简体中文). Pick one under
  **Language** in the menu, or follow the system.
- Launch at login.
- No camera, microphone, accessibility or network access needed. It only reads
  whether devices are busy, never their contents. Calendar access is asked for
  only if you turn on calendar meetings.

## Requirements

macOS 14 or later, and Xcode or the Xcode Command Line Tools (Swift 5.10+).

## Install

```bash
git clone https://github.com/Fengzdadi/EyeRest.git
cd EyeRest
make install
```

This builds `EyeRest.app`, signs it ad hoc for your own Mac, copies it to
`/Applications` and starts it. Turn on **Launch at Login** from the menu.

## Development

```bash
make run    # run from source
make demo   # a break every 15 s, lasting 5 s
make test   # unit tests for the break timer
make app    # build build/EyeRest.app without installing
```

Any setting can be overridden for one run, for example
`swift run EyeRest -workSeconds 600 -idleResetSeconds 300`.

| Setting | Default | Meaning |
|---|---|---|
| `workSeconds` | 1200 | Time between breaks |
| `breakSeconds` | 20 | Break length |
| `postponeSeconds` | 300 | How far "Postpone" pushes a break |
| `idleResetSeconds` | 120 | Idle time that counts as a natural break |
| `headsUpSeconds` | 10 | Heads-up before a break (0 turns it off) |
| `typingPauseSeconds` | 2 | A due break waits for this long without a key press |
| `maxTypingWaitSeconds` | 30 | Start the break anyway after waiting this long for a pause |
| `longBreakEvery` | 3 | Every Nth break is a long one (0 turns long breaks off) |
| `longBreakSeconds` | 300 | Long break length |
| `playSound` | true | Play a sound when a break ends |
| `graceSeconds` | 60 | Wait after a call or meeting ends before a held break |
| `holdDuringCalls` | true | Hold breaks while the camera or mic is in use |
| `holdDuringSlideshows` | true | Hold breaks during Keynote or PowerPoint slideshows |
| `holdDuringMeetings` | false | Hold breaks during calendar meetings |
| `showTimer` | true | Show the countdown in the menu bar |

To change one permanently: `defaults write io.github.fengzdadi.EyeRest idleResetSeconds -int 300`.

### What counts as busy

- **Call:** any app recording from the microphone, or any camera running.
  Some apps stop the mic when you mute, so a muted call with the camera off may
  not count; turn on calendar meetings to cover those.
- **Slideshow:** a Keynote or PowerPoint window covering a whole display.
  Editing a deck in native full screen looks the same, so it counts too.
- **Calendar meeting:** a timed event happening now that you haven't declined,
  with other attendees or a Zoom, Meet, Teams, Webex, FaceTime or Tencent
  Meeting link. Events marked "free" don't count.

macOS ties the calendar permission to the app's signature. The app is signed ad
hoc, so after a rebuild macOS may ask again.

To see what EyeRest is doing:
`/usr/bin/log stream --predicate 'subsystem == "io.github.fengzdadi.EyeRest"'`
(the full path matters in zsh, where `log` is a built-in command).

## How it works

The break logic lives in a small library, `EyeRestCore`, with no UI or system
calls. It reads the Mac's state through an `ActivityProbe`, so the tests in
`Tests/EyeRestCoreTests` drive it with a fake probe and made-up elapsed times.

| File | Role |
|---|---|
| `EyeRestCore/BreakTimer.swift` | The state machine: working, away, waiting while busy, waiting for a typing pause, on a break, paused |
| `BreakScheduler.swift` | Ticks the timer once a second and mirrors it into the break screen, heads-up and menu |
| `LiveProbe.swift` | The real `ActivityProbe`: idle time, screen lock, and the "Hold Breaks During" checks |
| `Activity.swift` | Idle time (`CGEventSource`), camera use (CoreMediaIO), microphone use per process (Core Audio), display-sleep assertions (IOKit), slideshow windows (`CGWindowList`) |
| `MeetingCalendar.swift` | Current calendar meeting (EventKit) |
| `HeadsUp.swift` | The countdown pill before a break; a panel that never becomes key |
| `BreakOverlay.swift` | Non-activating full-screen panels, so focus goes back to your app after the break |
| `StatusMenu.swift` | Menu bar icon, countdown and menu |
| `PanelSupport.swift` | Screen-under-mouse lookup and fade animations shared by the panels |
| `Resources/*.lproj` | Translations; the keys are the English text in the code |
| `scripts/make-icon.swift` | Draws the app icon: `swift scripts/make-icon.swift` |

## License

MIT
