# studydash

A study dashboard for [Omarchy](https://omarchy.org) that answers one question:
**am I on pace to finish my course by my deadline?**

It is built for one self-paced course with a percent-complete figure, such as a
TryHackMe or HackTheBox path, a Udemy course or a textbook. You can log study
sessions with a single key, and it reminds you to go back over finished topics
on a spaced schedule.

- **Overlay (SUPER+D):** a full-screen panel showing your course %, the pace
  you need against the pace you're actually keeping, study hours over the last
  four weeks against your weekly target, and the reviews that are due.
- **Session badge:** a small corner badge appears while a study session is
  running, so you can't forget one. Click it to stop the session.
- **`studydash` CLI:** this does all the logging and all the maths. The overlay
  only displays what the CLI writes.

## Requirements

- Omarchy, with its shell (Quickshell) plugin system
- Python 3.11 or newer (Omarchy ships with a newer one)
- A systemd user session (standard on Omarchy)

## Install

```bash
# 1. Add the overlay plugin
omarchy plugin add https://github.com/Abdullraaa/studydash --enable

# 2. Set up the CLI, your course, and the 15-minute refresh timer
~/.config/omarchy/plugins/ra.studydash/bin/studydash setup
```

`setup` asks for three things: the course name, the date you want to finish
by, and how many hours a week you're aiming for. It then:

- writes `~/.config/studydash/config.toml`
- links `~/.local/bin/studydash` to the CLI inside the plugin, so plugin
  updates update the CLI too
- installs and starts `studydash.timer`, which rebuilds the stats every 15
  minutes
- prints a checklist

You can safely run it again. To change your answers later, run
`studydash setup --reconfigure`.

```bash
# 3. Add keybinds: paste what setup printed into ~/.config/hypr/bindings.lua
o.bind("SUPER + D", "Study dashboard", "omarchy-shell shell toggle ra.studydash")
o.bind("SUPER + R", "Study session", "~/.local/bin/studydash session toggle")
o.bind("SUPER + ALT + R", "Reward break", "~/.local/bin/studydash reward toggle")
```

None of these keys is an Omarchy default, but your own config might already
use them. Check with `hyprctl binds` and change any that clash.

If you'd rather not be asked questions, pass the answers as flags:
`studydash setup --course "Jr Penetration Tester" --target 2027-03-01 --weekly-hours 5 --yes`.

## Daily use

| You want to… | Do |
|---|---|
| Start or stop studying | **SUPER+R**, or `studydash session toggle` (or click the badge to stop) |
| Record progress | `studydash log 42` (the course is now 42% done) |
| …and mark topics finished | `studydash log 42 --topic "Nmap: The Basics" --topic "Hashing Basics"` |
| Clear a review after redoing a topic | `studydash review nmap` (any unique start of the name works) |
| Take a timed break | **SUPER+ALT+R**, or `studydash reward start --topic gaming` |
| See everything in the terminal | `studydash status` |
| Look at the dashboard | **SUPER+D** (Esc or Q closes it, R reloads it) |

A *topic* is whatever your course breaks into: a TryHackMe room, a module, a
chapter.

## How the numbers are worked out

- **Course pace:** the pace you need is the % left divided by the weeks left.
  Your actual pace is how much your % rose over the last 28 days. The status
  is:
  - *ahead* if your actual pace is more than 10% above what you need
  - *on track* if it's within 10% either side
  - *behind* if it's lower than that
  - *behind* regardless of pace if you haven't logged progress for 10 days, or
    the target date has passed before you reached 100%
  - *unknown* when there's not yet enough data to measure a pace
- **Hours:** there's one bar for each of the last four Monday-start weeks.
  Sessions under a minute don't count, because they're almost always a
  mis-pressed key. Sessions over 4 hours count as 4 and are flagged on screen,
  because they're almost always a forgotten timer. After 3 hours you get a
  "still studying?" reminder.
- **Reviews:** a finished topic is due for review 7 days after you finish it.
  The next review is due 30 days after that one, then 90 days after that. A
  topic nobody has touched for 90 days is listed as *gone cold*.
  `studydash review` is deliberately the only way to clear a review, and you
  should run it only after you've actually redone the work.
- **Reward breaks:** these are tracked separately and never count as study.
  You get a reminder at 60 minutes, and a warning once a week's breaks pass
  2 hours.
- **Stale data:** if the dashboard's numbers are more than 45 minutes old
  (meaning the timer has stopped), the "updated" line turns red.

## Configuration

`~/.config/studydash/config.toml`. Only `[course]` is required. The template
that setup writes lists every other key, with its default, commented out.

| Key | Default | Meaning |
|---|---|---|
| `course.name` | | shown on the dashboard |
| `course.target_date` | | `YYYY-MM-DD`, the day you want to reach 100% |
| `course.weekly_hours` | `5` | weekly study target |
| `sessions.cap_hours` | `4` | longest a session can count for |
| `sessions.min_seconds` | `60` | shortest session that counts |
| `sessions.nudge_minutes` | `180` | when the "still studying?" reminder fires |
| `review.intervals` | `[7, 30, 90]` | days to each review, counted from the previous one |
| `review.cold_days` | `90` | days untouched before a topic is "gone cold" |
| `rewards.session_warn_minutes` | `60` | break reminder |
| `rewards.weekly_warn_minutes` | `120` | weekly break warning |
| `load.scan_roots` | `[]` | folders of git repos. Setting any turns on a card showing how many repos you committed to this week (other work competing with study) |
| `load.depth` | `2` | how deep to look for repos |

If a value is invalid, the CLI warns about it and uses the default instead.
Changes take effect at the next refresh, or run `studydash collect` to apply
them now.

## Your data

Everything lives in `~/.local/state/studydash/`. The logs (`sessions.jsonl`,
`progress.jsonl`, `rooms.jsonl`, `rewards.json`) are plain JSON Lines files.
studydash only ever appends to them; it never rewrites them. That means you
can back them up, edit them by hand, or change a setting and have it apply to
your whole history. `stats.json` is rebuilt from the logs on every refresh.

## Update and uninstall

```bash
omarchy plugin update ra.studydash   # updates the overlay and the CLI together
omarchy restart shell                # reload the overlay

studydash uninstall                  # removes the timer and the command; keeps your data
omarchy plugin remove ra.studydash
```

## Development

```bash
python3 -m unittest discover -s tests
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell -I /usr/lib/qt6/qml *.qml
```

## License

MIT
