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
  video (an app keeping the display awake) or sitting through a call without
  touching the keyboard doesn't count as away.
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
- **An MCP server for AI agents.** Agents such as Claude can read your break
  status and screen time (read-only). See [For AI agents](#for-ai-agents-mcp).
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

## For AI agents (MCP)

The app includes `eyerest-mcp`, a read-only [MCP](https://modelcontextprotocol.io)
server, so an agent can see whether you're due a break and how your day has
gone. It reads what the app records locally; agents can't change your settings
or breaks.

Add it to Claude Code:

```bash
claude mcp add --scope user eyerest -- /Applications/EyeRest.app/Contents/MacOS/eyerest-mcp
```

Or to Claude Desktop, in `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "eyerest": { "command": "/Applications/EyeRest.app/Contents/MacOS/eyerest-mcp" }
  }
}
```

| Tool | What it returns |
|---|---|
| `get_status` | Working, on a break, waiting, away or paused, and how long until the next break (and whether it's a long one) |
| `get_today` | Today's time at the screen, longest stretch without a break, and breaks finished, skipped and postponed |
| `get_history` | The same, one entry per day, for the last `days` days (default 7, at most 90) |

**What's recorded.** Time at the screen counts while there's recent keyboard
or mouse input, a video playing or a call, not which apps you use. Break
events and time at the screen go to `~/Library/Application Support/EyeRest/activity.jsonl`
(kept for 90 days), and the current state to `status.json` next to it.
Nothing leaves your Mac unless an agent reads it: what an agent reads becomes
part of its conversation with its model.

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
  The menu names the app using the microphone, so one that keeps it open is
  easy to spot. Some apps stop the mic when you mute, so a muted call with the
  camera off may not count; turn on calendar meetings to cover those. While
  calls hold breaks, a call also keeps you at the screen: listening without
  touching the keyboard or mouse isn't taken for being away.
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
| `EyeRestCore/BreakTimer.swift` | The state machine (working, away, waiting while busy, waiting for a typing pause, on a break, paused) and whether you're at the screen |
| `BreakScheduler.swift` | Ticks the timer once a second and mirrors it into the break screen, heads-up and menu |
| `LiveProbe.swift` | The real `ActivityProbe`: idle time, screen lock, and the "Hold Breaks During" checks, the slow ones reused for 5 seconds |
| `EyeRestCore/CachedCheck.swift` | Keeps a slow check's answer for a few seconds |
| `Activity.swift` | Idle time (`CGEventSource`), camera use (CoreMediaIO), microphone use per process and the app behind it (Core Audio), display-sleep assertions (IOKit), slideshow windows (`CGWindowList`) |
| `MeetingCalendar.swift` | Current calendar meeting (EventKit) |
| `HeadsUp.swift` | The countdown pill before a break; a panel that never becomes key |
| `BreakOverlay.swift` | Non-activating full-screen panels, so focus goes back to your app after the break |
| `StatusMenu.swift` | Menu bar icon, countdown and menu |
| `ActivityLogger.swift` | Writes the activity log and status file the MCP server reads |
| `EyeRestCore/ActivityLog.swift`, `DaySummary.swift`, `ActivityStore.swift` | Activity records, time at the screen, daily summaries, and the files they live in |
| `EyeRestMCP/MCPServer.swift` | The MCP server: JSON-RPC over stdio, three read-only tools |
| `PanelSupport.swift` | Screen-under-mouse lookup and fade animations shared by the panels |
| `Resources/*.lproj` | Translations; the keys are the English text in the code |
| `scripts/make-icon.swift` | Draws the app icon: `swift scripts/make-icon.swift` |

## License

MIT
