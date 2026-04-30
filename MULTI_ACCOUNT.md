# Running multiple Claude accounts on one machine

Sometimes you want several Ralph loops running in parallel terminals on the
same machine, each authenticated to a **different** Claude subscription —
e.g. a work account, a private account, a research account.

`claude` itself only knows one account at a time (whatever was last logged
in via `/login`). This fork ships a small helper, `with-claude-profile`,
that gives each profile its own isolated OAuth credentials so multiple
Claude accounts can be active simultaneously, one per terminal.

---

## How it works

`claude` stores its OAuth token in two HOME-relative paths:

- `$HOME/.claude/` (directory, contains `.credentials.json`, sessions, …)
- `$HOME/.claude.json` (settings file)

`with-claude-profile <name> <command>` runs `<command>` with `HOME` pointing
to `~/.claude-profiles/<name>/`. That directory is mostly a shadow of your
real `$HOME` — every entry is symlinked from the real home — *except*
`.claude` and `.claude.json`, which are real per-profile files. So each
profile has independent credentials, while npm, git, ssh, ralph, your
bashrc, etc. all keep working as usual.

```
~/.claude-profiles/work/
├── .bashrc      → ~/.bashrc       (symlink)
├── .nvm         → ~/.nvm          (symlink)
├── .gitconfig   → ~/.gitconfig    (symlink)
├── .ralph       → ~/.ralph        (symlink)
├── .local       → ~/.local        (symlink)
├── ...
├── .claude/     ← real, isolated  (work account credentials)
└── .claude.json ← real, isolated  (work account settings)
```

---

## Setup (one login per Claude account)

```bash
# First time only, per account:
with-claude-profile work claude       # → /login → use work email
with-claude-profile private claude    # → /login → use private email
with-claude-profile research claude   # → /login → use research email
```

Each `/login` writes the OAuth token into that profile's
`.claude/.credentials.json`. The three logins do **not** overwrite each
other — they live in separate directories.

The OAuth tokens auto-refresh in the background, so once a profile is
logged in it should stay logged in for a long time.

---

## Daily usage

Open one terminal per account, then:

```bash
# Terminal 1
with-claude-profile work bash ralph_wrapper.sh

# Terminal 2 (running at the same time)
with-claude-profile private bash ralph_wrapper.sh

# Terminal 3
with-claude-profile research bash ralph_wrapper.sh
```

All three Ralph loops run in parallel and pull tokens from three different
Claude subscriptions.

You can of course use `with-claude-profile <name>` for ad-hoc claude
commands too:

```bash
with-claude-profile work claude --print "what's in this repo?"
```

---

## Listing and removing profiles

```bash
ls ~/.claude-profiles/                    # list all profiles
rm -rf ~/.claude-profiles/<name>          # remove a profile (logs it out)
```

Removing the directory is enough — there's no global state about profiles
elsewhere.

---

## Per-profile tmux server

The wrapper sets `TMUX_TMPDIR=$PROFILE_HOME/.tmux` so each profile uses its
own tmux socket and therefore its own tmux server. Without this, the first
profile to run a tmux session would lock the user-global tmux server's
environment to its `HOME`, and any later session under a different profile
would silently inherit the first profile's `HOME` for shells spawned inside
— a classic tmux server-env leak.

The practical consequence: two profiles can run `ralph --monitor` in
parallel terminals without conflict. To list/attach to a profile's tmux
sessions you need to be inside that profile's wrapper, e.g.

```bash
with-claude-profile work tmux ls
with-claude-profile work tmux attach
```

## Caveats

- **Don't run two Ralph loops with the same profile in parallel.** They
  would share the same `.claude/sessions/` directory, which is not designed
  for concurrent writers. Use one profile per running loop.
- **Profile name is restricted to `[a-zA-Z0-9_-]+`** because it's used as a
  directory name. No spaces, no slashes.
- **The symlinks are refreshed on every invocation.** If you add a new
  top-level entry to your real `$HOME` (e.g. a new dotfile), the next
  `with-claude-profile` call will link it into existing profiles too.
- **Tokens may eventually expire.** If a profile suddenly fails auth, just
  re-run `with-claude-profile <name> claude` and `/login` again.
