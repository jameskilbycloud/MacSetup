# MacSetup — Headless Server Profile

Setup for a Mac mini that runs **headless as a server**: no monitor, no keyboard,
reached only over SSH and the occasional Screen Sharing session.

This is a sibling to the desktop setup in the repo root, not a replacement.
`git-setup.sh` and `zsh-setup.sh` are shared; everything else here is separate,
because a server and a daily driver want opposite things.

## Requirements

**Apple silicon (M-series) only.** Every script calls `require_apple_silicon`
and exits on anything else, because the profile hard-assumes it: Homebrew at
`/opt/homebrew`, Colima on Virtualization.framework with Rosetta, and the
`osx-arm64` Actions runner build. The check reads `hw.optional.arm64` rather
than `uname -m`, so it also catches a shell running translated under Rosetta —
which would otherwise resolve Homebrew to `/usr/local` and pick the wrong VM
backend.

## How it differs from the desktop profile

| | Desktop (`/install.sh`) | Server (`server/install-server.sh`) |
|---|---|---|
| GUI apps | ~20 casks (Chrome, VS Code, Adobe, Signal…) | 1 cask (Plex Media Server) |
| Containers | Docker Desktop | Colima + docker CLI |
| Sleep | macOS defaults | Never sleeps; auto-restarts after power loss or freeze |
| Remote access | — | SSH key-only, Screen Sharing as escape hatch |
| Dotfile sync | Mackup via iCloud | None — iCloud needs a GUI sign-in and a server shouldn't hold personal credentials |
| App Store | `mas-apps.sh` | Dropped — `mas` needs an interactive App Store sign-in |
| Updates | Manual | Security updates automatic, macOS upgrades manual |
| Maintenance | Run `brew-maintenance.sh` when you remember | Weekly LaunchAgent |
| Nerd Font | Installed | Skipped (`MACSETUP_SKIP_FONT=1`) |

## Quick start

If the Mac is already set up and you just want to run the profile:

```shell
git clone https://github.com/jameskilbynet/MacSetup.git
cd MacSetup
chmod +x *.sh server/*.sh
./server/install-server.sh
```

Run it **from the physical console or an existing Screen Sharing session** the
first time. The SSH step can lock you out if you get it wrong, and a couple of
macOS toggles need a GUI to approve.

Every step is prompted and skippable. A failed step doesn't abort the run — you
get a summary at the end listing what was skipped and what failed.

For a Mac that came out of the box an hour ago, work through the walkthrough
below instead. Several of the decisions it covers are made during Setup
Assistant and are painful to reverse afterwards.

---

# From a factory-fresh Mac mini

The whole of Phases 0–4 happens **with a monitor and keyboard attached**. You
unplug them at the end, in Phase 5, once you've proved you can get back in
without them.

## Phase 0 — Before you power it on

| | |
|---|---|
| **Display** | Any HDMI monitor or TV. Needed for Setup Assistant — macOS has no headless first-boot path. |
| **Keyboard** | USB or Bluetooth. A USB keyboard is easier; Bluetooth pairing during Setup Assistant works but is fiddly. |
| **Network** | **Wired ethernet.** Wi-Fi works, but a server that drops off the network when the AP reboots isn't a server. |
| **DHCP reservation** | Pin the mini's MAC to a fixed IP on your router *now*. Easier than configuring a static IP on the Mac, and it survives a macOS reinstall. |
| **Power** | A UPS if you have one. `autorestart` brings the box back after a cut, but it can't protect a write in flight. |

Optional but worth having: an **HDMI dummy plug** (~£5). A Mac mini with no
display attached reports a small default resolution to Screen Sharing; a dummy
plug keeps it at something usable. You only need this if you plan to use Screen
Sharing regularly.

## Phase 1 — Setup Assistant

These choices matter more than usual, because three of them are hard to undo
and two of them will silently break the unattended-reboot behaviour.

| Screen | Choose | Why |
|---|---|---|
| Country / Language | as you like | — |
| **Accessibility** | Skip | — |
| **Wi-Fi / Network** | Use the ethernet connection | If it offers Wi-Fi anyway, connect ethernet first and it'll skip ahead |
| **Migration Assistant** | **Not Now** | A clean server, not a copy of a laptop |
| **Apple ID** | **Set Up Later** → confirm Skip | A server shouldn't hold your personal iCloud credentials. You can sign in later if you specifically need the App Store. |
| **Terms** | Agree | — |
| **Create a Computer Account** | ⚠️ See below | This account name becomes your SSH username |
| **Enable Location Services** | Off | — |
| **Time Zone** | Set it manually | Location Services is off, so it can't infer one |
| **Analytics / Crash reports** | Off | — |
| **Screen Time** | Set Up Later | — |
| **Siri** | Off | — |
| **FileVault** (if offered) | ⚠️ See below | Conflicts with automatic login |
| **Touch ID / Apple Pay** | Skip | — |

### ⚠️ The account you create is your SSH username

Pick it deliberately — `admin`, `server`, your usual handle, whatever. Renaming
a macOS account afterwards is genuinely awkward. Give it a **strong local
password** and store it in your password manager; you'll need it for `sudo`,
for Screen Sharing, and for physical recovery.

**Do not tie the login password to an Apple ID.** If the account uses "Use your
iCloud password to log in", macOS greys out automatic login entirely — and this
profile needs automatic login to work (see below). Skipping Apple ID in Setup
Assistant avoids this by default.

### ⚠️ FileVault: decide now

FileVault and automatic login are mutually exclusive, and this profile depends
on automatic login for Colima, Plex and the Actions runner to come back after a
reboot.

- **Turn FileVault off** if the mini lives somewhere physically secure (a locked
  cupboard, your own house). Reboots come back completely unattended. **This is
  the right choice for most home servers.**
- **Leave FileVault on** if the machine could be physically stolen. Accept that
  every reboot needs `sudo fdesetup authrestart` issued *beforehand*, and that
  an unplanned power cut leaves the box sitting at the login screen until you
  physically unlock it.

Turning FileVault off later is possible (System Settings → Privacy & Security),
but it has to decrypt the whole disk first. Cheaper to get it right here.

## Phase 2 — Prepare the desktop session

Log in and do these four things before touching the scripts.

### 1. Install the Xcode Command Line Tools

Homebrew needs them, and the installer is a GUI dialog — so get it done while
you have a screen.

```shell
xcode-select --install
```

Click through the prompt and wait for it to finish (a few minutes). Verify:

```shell
xcode-select -p     # should print /Library/Developer/CommandLineTools
```

`install-server.sh` will trigger this for you if you skip it, but it then exits
so you can finish the GUI prompt — doing it first saves a round trip.

### 2. Grant Terminal Full Disk Access

**This is the single most useful thing you can do before running the scripts.**

Since macOS 10.14, `systemsetup -setremotelogin` (Remote Login) and the Screen
Sharing `kickstart` both require the *calling terminal* to hold Full Disk
Access. No script can grant itself that. Without it, the SSH and Screen Sharing
steps detect the failure and fall back to telling you to flip the switches by
hand — which works, but is more clicking than doing this once:

1. **System Settings → Privacy & Security → Full Disk Access**
2. Click **+**, go to **Applications → Utilities**, add **Terminal**
3. Toggle it on
4. **Quit Terminal completely** (⌘Q — not just closing the window) and reopen it

The permission only takes effect in a freshly launched Terminal.

### 3. Check you're on ethernet with the address you expect

```shell
ipconfig getifaddr en0     # ethernet on a Mac mini
networksetup -listallhardwareports
```

Confirm it matches the DHCP reservation you made in Phase 0.

### 4. Stop the machine sleeping mid-install

A fresh Mac will happily sleep during a long `brew install`. `power-setup.sh`
fixes this permanently, but it runs partway through — so hold it awake for now:

```shell
caffeinate -dims &
```

That backgrounds a keep-awake assertion for the rest of the session; it goes
away on reboot, by which point `power-setup.sh` has made it unnecessary.

## Phase 3 — Get the repo and run it

```shell
cd ~
git clone https://github.com/jameskilbynet/MacSetup.git
cd MacSetup
chmod +x *.sh server/*.sh
./server/install-server.sh
```

<details>
<summary>No <code>git</code> yet? (i.e. you skipped step 2.1)</summary>

`curl` and `tar` ship with macOS and need no Command Line Tools:

```shell
cd ~
curl -fsSL https://github.com/jameskilbynet/MacSetup/archive/refs/heads/master.tar.gz | tar xz
cd MacSetup-master
chmod +x *.sh server/*.sh
./server/install-server.sh
```

You'll still need the Command Line Tools before Homebrew will install.
</details>

### What to expect, step by step

The installer prompts before each step and prints a summary at the end. Ten
steps, roughly 30–60 minutes depending on your connection — `brew-server.sh` is
the overwhelming majority of it.

| # | Step | Notes |
|---|---|---|
| 1 | **Homebrew & Server Packages** | The long one. Installs Homebrew, ~44 formulas and Plex. Leave it running. |
| 2 | **Git Configuration** | Prompts for `user.name` / `user.email` if unset |
| 3 | **Zsh & Oh-My-Zsh** | Asks to reinstall if Oh-My-Zsh exists; on a fresh Mac it won't |
| 4 | **macOS Server Defaults** | Prompts for a **hostname** — this becomes `<name>.local`. Also asks about disabling Spotlight (defaults to No). |
| 5 | **Power Management** | Needs `sudo`. Prints your power settings at the end. |
| 6 | **SSH Access** | ⚠️ See below — the step with real consequences |
| 7 | **Screen Sharing** | Prompts for which user to grant access to |
| 8 | **Container Runtime** | Offers to install Rosetta, then prompts for VM CPU/RAM/disk. Defaults are sensible. |
| 9 | **GitHub Actions Runner** | Defaults to **No**. Say yes only if you want CI on this box. |
| 10 | **Unattended Maintenance** | Installs the weekly LaunchAgent |

### ⚠️ Step 6 in detail — don't lock yourself out

This is the only step that can cost you access. It's built to make that hard,
but understand what it's doing:

1. It enables Remote Login.
2. It asks you to install public keys — **from GitHub (option 1) is easiest**:
   enter your GitHub username and it fetches `https://github.com/<you>.keys`.
   You can add several; it loops until you choose Done.
3. It reports how many keys are installed, then asks whether to disable password
   authentication. **It refuses outright if that count is zero.**
4. It validates the config with `sshd -T` before reloading, and rolls the change
   back automatically if sshd rejects it.

**Before you answer yes to "Disable password authentication?", open a second
Terminal window and confirm the key actually works:**

```shell
ssh <youruser>@<hostname>.local
```

If that fails, answer **No**, fix the key, and re-run `./server/ssh-setup.sh`.
Nothing else in the profile depends on this step succeeding.

## Phase 4 — The three things the scripts can't do

`install-server.sh` prints these at the end. They need the GUI, which is why
you still have a monitor attached.

### 1. Enable automatic login ← the important one

Colima, Plex Media Server and the Actions runner are all **LaunchAgents**. They
only start inside a logged-in user session. Without automatic login, the mini
reboots and comes back with none of them running — which quietly defeats the
`autorestart` setting you just configured.

**System Settings → Users & Groups → Automatically log in as… → \<your account\>**

If the option is greyed out, it's one of:
- FileVault is on (see Phase 1)
- The account uses its Apple ID password to log in
- The account is a "Sharing Only" or non-admin account

### 2. Claim the Plex server

From any machine on the LAN:

```
http://<hostname>.local:32400/web
```

Sign in to your Plex account to claim it. Until you do, it's an unconfigured
server that anyone on your network can adopt.

### 3. Verify, then reboot

```shell
./server/healthcheck.sh
```

Fix anything reporting `[ERROR]`, then reboot and run it again:

```shell
sudo reboot
# ...wait, then from your laptop:
ssh <youruser>@<hostname>.local './MacSetup/server/healthcheck.sh'
```

**That second run is the real test.** It proves the box comes back on its own
with SSH, containers and Plex all running — which is exactly what you're relying
on once the monitor is gone.

## Phase 5 — Go headless

Only once the post-reboot healthcheck passes over SSH:

1. Confirm Screen Sharing works too — `open vnc://<hostname>.local` from your
   laptop. This is your escape hatch when SSH isn't enough; test it while you
   still have a fallback.
2. Shut down: `sudo shutdown -h now`
3. Unplug the monitor and keyboard. Fit the HDMI dummy plug if you have one.
4. Power on. Wait a minute or two for boot + auto-login.
5. From your laptop:

```shell
ssh <youruser>@<hostname>.local './MacSetup/server/healthcheck.sh'
```

Green across the board means it's a server now.

## If you get locked out

In rough order of how much you'll hate it:

| Symptom | Fix |
|---|---|
| SSH refuses your key | Get in via Screen Sharing (`vnc://<hostname>.local`), then `sudo rm /etc/ssh/sshd_config.d/100-macsetup-server.conf && sudo launchctl kickstart -k system/com.openssh.sshd` |
| SSH *and* Screen Sharing both dead | Plug the monitor and keyboard back in. Everything is recoverable from the console. |
| Box doesn't come back after a reboot | Almost always FileVault or missing automatic login. Attach a display and check Phase 4.1. |
| Containers/Plex missing after reboot, SSH fine | Automatic login is off — Phase 4.1 |
| Forgot the account password | Boot to Recovery (hold the power button on Apple silicon) → Utilities → Terminal → `resetpassword` |

---

## Or run steps individually

```shell
./server/brew-server.sh        # Homebrew, CLI/DevOps tooling, containers, Plex
./git-setup.sh                 # shared with desktop
MACSETUP_SKIP_FONT=1 ./zsh-setup.sh
./server/defaults-server.sh    # hostname, no modal dialogs, no App Nap
./server/power-setup.sh        # never sleep, restart on power loss/freeze
./server/ssh-setup.sh          # Remote Login + key-only auth
./server/screen-sharing.sh     # Remote Management
./server/docker-setup.sh       # Colima
./server/ci-runner-setup.sh    # GitHub Actions runner (optional)
./server/maintenance-setup.sh  # weekly LaunchAgent
./server/healthcheck.sh        # verify everything (read-only, safe any time)
```

## Scripts

### `brew-server.sh`
Homebrew plus a server-shaped package list. Keeps the DevOps tooling from the
desktop profile (ansible, terraform, vault, packer, kubectl, k9s, helm, govc,
awscli) and adds:

- **Containers** — `colima`, `docker`, `docker-compose`, `docker-buildx`, `lazydocker`
- **Remote ops** — `mosh`, `tmux`, `iperf3`, `mtr`, `rsync` (macOS still ships rsync 2.6.9)
- **Backup** — `restic`, `rclone`
- **Casks** — `plex-media-server` only

Drops `mackup`, `mas` and `asciinema`; adds `bat`, which the shared zsh aliases
have always referenced but the desktop `brew.sh` never installed.

### `defaults-server.sh`
macOS defaults for a machine nobody is looking at:

- **Identity** — optionally sets ComputerName / HostName / LocalHostName / NetBIOS
- **Nothing modal** — crash reporter dialogs off, no Time Machine disk prompts,
  no window restore on login, notification banners suppressed. A modal dialog on
  a headless box is a process that never exits.
- **No throttling** — App Nap and automatic app termination disabled, so a
  background service that looks idle to macOS isn't slowed down or killed.
  Screen saver never starts.
- **Updates** — security responses and system data files install automatically;
  macOS major upgrades stay manual, because an unattended upgrade reboot can
  break Colima, the runner and Plex in one go.
- **Spotlight** — optionally disabled on the boot volume (prompted, off by default)

Deliberately leaves Gatekeeper quarantine alone — disabling it is a common
"server tweak" that removes a real defence for no benefit on a headless box.

### `power-setup.sh`
The most important script here. A stock Mac mini sleeps, and a sleeping server
is an outage.

- System and disk sleep: never (display sleep stays on — blanking an output
  nobody watches suspends nothing)
- `autorestart 1` — comes back after a power cut
- `setrestartfreeze on` — comes back after a kernel panic
- `womp 1` — wake on network access
- Power Nap: off
- `ttyskeepawake 1` — a long SSH job is never cut short by a sleep transition

Doesn't touch `standby` / `autopoweroff` / `hibernatemode`: those tune the Intel
suspend-to-disk path and are inert on Apple silicon, which manages its own
low-power states. With `sleep 0` set there's nothing for them to do anyway.

Settings are still applied through a tolerant `try` wrapper — the supported
`pmset` key set shifts between macOS releases, and one rejection shouldn't
abort the run.

Warns if FileVault is on — see the trade-off below.

### `ssh-setup.sh`
Key-only SSH, in a deliberately safe order: **keys are installed and counted
before password authentication is switched off.** The script refuses to disable
passwords if `~/.ssh/authorized_keys` is empty.

- Enables Remote Login (and explains the Full Disk Access requirement when
  macOS blocks the CLI toggle — see Gotchas)
- Installs public keys from GitHub (`https://github.com/<user>.keys`), a paste,
  or a local `.pub` file
- Writes `/etc/ssh/sshd_config.d/100-macsetup-server.conf` — a drop-in, so macOS
  updates that replace `sshd_config` don't wipe the hardening
- Verifies `Include /etc/ssh/sshd_config.d/*` is present *and first* in
  `sshd_config` (sshd uses the first value it obtains for each keyword)
- Validates with `sshd -T` before reloading, and removes the drop-in if invalid
- Prints the exact rollback command and tells you to test from a second terminal

Settings: `PasswordAuthentication no`, `KbdInteractiveAuthentication no`,
`PermitRootLogin no`, `MaxAuthTries 3`, `LoginGraceTime 30`, `X11Forwarding no`,
`ClientAlive*` keepalives. `UsePAM` stays `yes` — macOS needs it for session setup.

**Rollback if you lock yourself out of SSH:** connect via Screen Sharing or the
console and run

```shell
sudo rm /etc/ssh/sshd_config.d/100-macsetup-server.conf
sudo launchctl kickstart -k system/com.openssh.sshd
```

### `screen-sharing.sh`
Enables Remote Management for the handful of macOS tasks with no headless path:
App Store sign-in, claiming Plex, granting Full Disk Access, clearing a modal
that appeared anyway.

Access is restricted to named users and authenticated with the macOS account
password. The legacy VNC password is **not** enabled — it's a weak, separately
stored shared secret. Reach it at `vnc://<hostname>.local`; don't port-forward
5900 to the internet.

### `docker-setup.sh`
Colima instead of Docker Desktop, because Docker Desktop is a GUI app that won't
start without a logged-in Aqua session.

- Sizes the VM from the hardware (half the cores, half the RAM, 100GB disk by
  default — all prompted)
- Uses Virtualization.framework + virtiofs
- Installs Rosetta if missing and passes `--vz-rosetta`, so x86-only images still
  run. A fresh Apple silicon Mac has never installed Rosetta and Colima fails at
  start rather than degrading, so this is checked up front — decline it and the
  VM starts arm64-only instead
- Registers with `brew services` for autostart
- Verifies by running `hello-world` and checking the compose plugin

### `ci-runner-setup.sh`
Optional GitHub Actions self-hosted runner. Downloads the official `osx-arm64`
release into `~/actions-runner`, mints a registration token via `gh`
(or takes a pasted one), registers against a repo or org, and installs it as a
launchd service.

**Only attach this to repositories you trust.** A self-hosted runner executes
whatever CI jobs it's sent, as your user, on this machine — never point one at a
public repo that accepts fork pull requests.

### `maintenance-setup.sh`
Weekly LaunchAgent (Sundays 04:00) running the shared `brew-maintenance.sh full`,
niced and low-priority-IO so it doesn't compete with real workloads. Logs to
`~/Library/Logs/MacSetup/maintenance.log` with newsyslog rotation.

```shell
launchctl list | grep macsetup                                   # is it loaded
launchctl kickstart -k gui/$(id -u)/cloud.jameskilby.macsetup.maintenance  # run now
tail -f ~/Library/Logs/MacSetup/maintenance.log                  # watch it
```

### `healthcheck.sh`
Read-only verification, safe to run any time. Checks disk space, power settings,
sshd and authorised keys, automatic login, FileVault, Colima/docker, Plex, the
Actions runner, and the maintenance agent. Exits non-zero on any failure, so it
works from a monitoring job too.

```shell
./server/healthcheck.sh
```

## Gotchas — the short version

Four macOS behaviours account for nearly every "why isn't my server working"
moment. The walkthrough above covers each in context; this is the summary.

| Gotcha | Effect | Where |
|---|---|---|
| **Automatic login is effectively required** | Colima, Plex and the Actions runner are LaunchAgents — they only start inside a logged-in session. Without it, a reboot comes back with none of them running, quietly defeating `autorestart 1`. | [Phase 4.1](#1-enable-automatic-login--the-important-one) |
| **FileVault blocks automatic login** | An encrypted Mac stops at the login screen after a reboot. `sudo fdesetup authrestart` unlocks the *next boot only* — fine for planned reboots, no help after a power cut. | [Phase 1](#%EF%B8%8F-filevault-decide-now) |
| **Full Disk Access for CLI toggles** | Since macOS 10.14, `systemsetup -setremotelogin` and the Screen Sharing `kickstart` need the *calling terminal* to hold FDA. No script can grant itself that. | [Phase 2.2](#2-grant-terminal-full-disk-access) |
| **Plex needs claiming from a browser** | Until claimed at `http://<hostname>.local:32400/web`, it's an unconfigured server anyone on your LAN can adopt. | [Phase 4.2](#2-claim-the-plex-server) |

`power-setup.sh` warns about FileVault at install time, and `healthcheck.sh`
reports the state of all four whenever you run it.

**And one rule:** run the first install from the physical console, never over
SSH. The SSH hardening step can drop your own session, and you want a way back
in that doesn't depend on the thing you're changing.
