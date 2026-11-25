# studydash

Study pace dashboard: a Python collector/CLI plus an Omarchy Quickshell overlay.

| Repo path   | Live location                                   |
|-------------|-------------------------------------------------|
| `bin/studydash` | `~/.local/bin/studydash`                    |
| `plugin/`   | `~/.config/omarchy/plugins/ra.studydash/`       |
| `systemd/`  | `~/.config/systemd/user/`                       |

Data lives in `~/.local/state/studydash/` and is not part of this repo.

Deploy:

```bash
install -m755 bin/studydash ~/.local/bin/studydash
rsync -a --delete plugin/ ~/.config/omarchy/plugins/ra.studydash/
omarchy restart shell   # only needed for QML changes
```
