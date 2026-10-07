# Herdr Session Manager for Omarchy

Interactive session picker, launcher, and manager for [Herdr](https://herdr.dev) AI coding agent sessions.

![Herdr Session Manager](preview.png)

Requires [herdr](https://herdr.dev) (ships with Omarchy).

---

### Step 1: Install

```bash
omarchy plugin add https://github.com/houtvongsak/omarchy-herdr-sessions.git --enable
```

---

### Step 2: Add Shortcut

Run this command in your terminal to bind **`Super + Ctrl + Enter`**:

```bash
cat << 'EOF' >> ~/.config/hypr/bindings.lua

-- Herdr Session Picker
hl.unbind("SUPER + CTRL + RETURN")
o.bind("SUPER + CTRL + RETURN", "Herdr Session Manager", "omarchy-shell shell toggle io.github.houtvongsak.herdr-sessions")
EOF
hyprctl reload
```

*(Or edit manually with `nano ~/.config/hypr/bindings.lua` and run `hyprctl reload`).*

---

### Step 3: Use It

Press **`Super + Ctrl + Enter`**:

| Key | Action |
|---|---|
| `↑` / `↓` | Select session |
| `Enter` | Launch / attach to session |
| `n` | Create new session |
| `s` | Stop running session |
| `d` / `Delete` | Delete stopped session |
| `Esc` | Clear filter / Close picker |

---

### Remote Machines

SSH machines saved in herdr (herdr 0.9 or newer) show up below your local sessions, marked **remote**, with whether they can be reached right now:

```bash
herdr machine add you@buildbox
herdr machine add you@buildbox --remote-session agents   # another session on the same host
```

- A saved machine points at one session on its host, so each one is a row. Save the host again with `--remote-session <name>` to list another of its sessions.
- `Enter` opens it in a terminal with `herdr --remote <target> [--session <name>]`. If SSH needs a passphrase or a new host key, it asks there.
- Typing filters remote rows by label, SSH target or session name.
- Stop and delete stay local: herdr doesn't manage sessions on saved machines. Disabled machines are left out.

---

### Removal

Remove the plugin and restore the original `Super + Ctrl + Enter` (opens default herdr):

```bash
omarchy plugin remove io.github.houtvongsak.herdr-sessions
sed -i '/^-- Herdr Session Picker$/,/herdr-sessions")$/d' ~/.config/hypr/bindings.lua
hyprctl reload
```

### License

MIT
