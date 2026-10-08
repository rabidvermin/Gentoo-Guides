# Offline Speech-to-Text Dictation on Gentoo KDE Plasma

Local speech recognition on KDE Plasma Wayland using Vosk, nerd-dictation, and ydotool.

Press `Meta+Space` once to begin recording, speak, then press it again to transcribe and type the result into the currently focused application, including Konsole.

> **Last updated:** 2026-10-08
>
> **Tested with:** Gentoo Linux, OpenRC, KDE Plasma Wayland, PipeWire, fish, and a Poly Blackwire USB headset.

---

## Table of Contents

1. [How It Works](#how-it-works)
2. [Install Dependencies](#step-1-install-dependencies)
3. [Configure uinput](#step-2-configure-uinput)
4. [Install nerd-dictation](#step-3-install-nerd-dictation)
5. [Install a Vosk Model](#step-4-install-a-vosk-model)
6. [Configure Spoken Punctuation](#step-5-configure-spoken-punctuation)
7. [Create the Toggle Script](#step-6-create-the-toggle-script)
8. [Choose a Startup Path](#step-7-choose-a-startup-path)
9. [Fresh Plasma Login](#step-8a-fresh-plasma-login)
10. [Existing Plasma Session](#step-8b-existing-plasma-session-without-logging-out)
11. [Create the KDE Shortcut](#step-9-create-the-kde-shortcut)
12. [Start ydotoold Automatically](#step-10-start-ydotoold-automatically)
13. [Testing](#testing)
14. [Troubleshooting](#troubleshooting)
15. [Security Notes](#security-notes)
16. [References](#references)

---

## How It Works

The components have separate responsibilities:

- **parec** records audio from the default PipeWire/PulseAudio microphone.
- **Vosk** performs local, offline speech recognition.
- **nerd-dictation** manages recording and transcription.
- **ydotoold** creates a virtual keyboard through `/dev/uinput`.
- **ydotool** types the recognized text into the focused application.
- **KDE Plasma** provides the global `Meta+Space` shortcut.

No audio is sent to an external speech-recognition service.

> This setup uses a toggle rather than a literal hold-to-talk key. Press the shortcut once to start and again to stop.

---

## Conventions

This guide uses `doas` for privilege escalation. If you are already root, omit `doas`.

Fish does not support bash heredocs (`<<EOF`). The file-creation commands below use `printf`, which works in both fish and bash.

---

## Step 1. Install Dependencies

```bash
doas emerge --ask \
    app-arch/unzip \
    dev-vcs/git \
    media-libs/libpulse \
    net-misc/wget \
    sys-process/procps \
    x11-misc/ydotool
```

`procps` provides `pgrep`, which the toggle script uses. `libpulse` provides `parec`.

Confirm that the required commands are available:

```bash
command -v parec
command -v python3
command -v pgrep
command -v ydotool
command -v ydotoold
```

### Kernel requirement

`ydotoold` requires the Linux `uinput` interface. Load it now:

```bash
doas modprobe uinput
ls -l /dev/uinput
```

If `modprobe uinput` fails, ensure the kernel has one of the following:

```text
CONFIG_INPUT_UINPUT=y
```

or:

```text
CONFIG_INPUT_UINPUT=m
```

---

## Step 2. Configure uinput

Create a udev rule that grants the `input` group access to `/dev/uinput`:

```bash
printf '%s\n' \
  'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"' |
  doas tee /etc/udev/rules.d/80-uinput.rules >/dev/null
```

Add your user to the `input` group:

```bash
doas gpasswd -a "$USER" input
```

Reload the rule:

```bash
doas udevadm control --reload
doas udevadm trigger
doas modprobe uinput
```

> **Security warning:** Membership in the `input` group may grant access to input devices beyond `/dev/uinput`, depending on the system's other udev rules. Only grant this membership to trusted local users.

Group membership is applied when a login session starts. It is not applied to a Plasma session that is already running. The two startup paths below cover that difference.

---

## Step 3. Install nerd-dictation

Clone nerd-dictation into the user's local data directory:

```bash
mkdir -p ~/.local/share
git clone https://github.com/ideasman42/nerd-dictation.git \
    ~/.local/share/nerd-dictation
```

Create an isolated Python environment and install Vosk:

```bash
python3 -m venv ~/.local/share/nerd-dictation/.venv
~/.local/share/nerd-dictation/.venv/bin/pip install vosk
```

Using a virtual environment avoids modifying Gentoo's system-managed Python packages.

The version tested for this guide used nerd-dictation commit:

```text
41f372789c640e01bb6650339a78312661530843
```

To use that exact revision:

```bash
git -C ~/.local/share/nerd-dictation checkout \
    41f372789c640e01bb6650339a78312661530843
```

---

## Step 4. Install a Vosk Model

Download the small US English model:

```bash
mkdir -p ~/.config/nerd-dictation
cd ~/.config/nerd-dictation

wget https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip
unzip vosk-model-small-en-us-0.15.zip
mv vosk-model-small-en-us-0.15 model
```

Confirm the model exists:

```bash
ls ~/.config/nerd-dictation/model
```

Expected directories include:

```text
am
conf
graph
ivector
```

Other languages and larger models are available from the Vosk model page. Larger models generally improve accuracy but use more memory and take longer to load.

---

## Step 5. Configure Spoken Punctuation

The small Vosk model recognizes words but does not automatically infer punctuation. nerd-dictation can replace spoken commands such as "period" and "question mark" before typing the result.

Create the directory and save this file as `~/.config/nerd-dictation/nerd-dictation.py`. Copy the Python below into an editor. A shell one-liner is a poor fit here because the punctuation characters collide with shell quoting, especially in fish.

```bash
mkdir -p ~/.config/nerd-dictation
```

```python
# Spoken punctuation for nerd-dictation.

CLOSING_PUNCTUATION = {
    "question mark": "?",
    "exclamation point": "!",
    "exclamation mark": "!",
    "period": ".",
    "comma": ",",
    "colon": ":",
    "semicolon": ";",
    "dash": "-",
    "hyphen": "-",
    "close quote": '"',
    "apostrophe": "'",
}

OPENING_PUNCTUATION = {
    "open quote": '"',
}


def nerd_dictation_process(text):
    for match, replacement in CLOSING_PUNCTUATION.items():
        text = text.replace(" " + match, replacement)

    for match, replacement in OPENING_PUNCTUATION.items():
        text = text.replace(match + " ", replacement)

    return text
```

Examples:

| Spoken words | Typed result |
|---|---|
| `this is a test period` | `this is a test.` |
| `is this working question mark` | `is this working?` |
| `yes comma it is working` | `yes, it is working` |
| `warning colon disk is full` | `warning: disk is full` |

A spoken newline is intentionally not configured. In a terminal, generating a real newline would press Enter and could execute the recognized command.

Saying "period" always becomes `.`, including in a phrase such as "period of time."

---

## Step 6. Create the Toggle Script

Create `~/.local/bin/dictate-toggle`:

```bash
mkdir -p ~/.local/bin ~/.cache
cat > ~/.local/bin/dictate-toggle << 'EOF'
#!/bin/sh
ND="$HOME/.local/share/nerd-dictation/nerd-dictation"
PY="$HOME/.local/share/nerd-dictation/.venv/bin/python"
LOG="$HOME/.cache/dictate-toggle.log"
export PATH="$HOME/.local/share/nerd-dictation/.venv/bin:$PATH"

if pgrep -u "$(id -u)" -f "nerd-dictation begin" >/dev/null; then
    exec "$PY" "$ND" end >>"$LOG" 2>&1
fi

rm -f /tmp/nerd-dictation.cookie
echo "=== begin $(date) ===" >>"$LOG"
exec "$PY" "$ND" begin --sample-rate=16000 --simulate-input-tool=YDOTOOL >>"$LOG" 2>&1
EOF
chmod +x ~/.local/bin/dictate-toggle
```

Fish does not support that heredoc. From fish, write the same script with an editor, or run `bash` and paste the block above.

The 16 kHz sample rate matches the Vosk model and many speech-oriented USB headsets. The first press starts recording. The second press transcribes and types the result. A stale `/tmp/nerd-dictation.cookie` is removed before a new recording starts, so a previous crashed session does not block the toggle.

---

## Step 7. Choose a Startup Path

There are two valid ways to start `ydotoold`:

1. **Fresh Plasma login:** log out and back in so the entire session inherits the `input` group.
2. **Existing Plasma session:** use `sg` to grant only `ydotoold` the new group without closing applications or logging out.

The second option is for a session that already has terminals, browser tabs, virtual machines, remote connections, or other work that cannot be interrupted.

### Confirm the account membership

First, confirm that the account has been added to the group database:

```bash
id "$USER"
```

This should list `input`.

Now inspect the groups inherited by the current shell:

```bash
id
```

Immediately after adding the account to `input`, these commands can produce different results:

```text
$ id "$USER"
... groups=...,97(input),...

$ id
... groups=...
```

This is normal. `id "$USER"` queries the current account database, while `id` shows the groups inherited by the current Plasma session.

Opening another terminal does not create a new login session and therefore does not refresh its groups.

Use [Step 8A](#step-8a-fresh-plasma-login) when logging out is convenient. Use [Step 8B](#step-8b-existing-plasma-session-without-logging-out) when it is not.

---

## Step 8A. Fresh Plasma Login

Use this path when it is convenient to close the current desktop session.

Completely log out through:

```text
Application Launcher → Leave → Log Out
```

Then sign back in and verify:

```bash
id
```

The current session should now list `input`.

Start the daemon normally:

```bash
ydotoold &
disown
```

Verify it:

```bash
pgrep -a -u "$(id -u)" ydotoold
ls -l /run/user/"$(id -u)"/.ydotool_socket
```

The process and socket must belong to the desktop user.

A message similar to this is expected:

```text
Socket path: /run/user/1000/.ydotool_socket
Socket permission: 0600
READY
```

The user ID may differ. This warning is harmless on Wayland:

```text
xinput command not found, not disabling mouse pointer acceleration
```

Continue with the [KDE shortcut](#step-9-create-the-kde-shortcut) and then [automatic startup](#step-10-start-ydotoold-automatically).

> Do not run `ydotoold` with `doas`. A root-owned socket with mode `0600` cannot be used by the KDE shortcut running as your normal user.

---

## Step 8B. Existing Plasma Session Without Logging Out

Use this path when the account has been added to `input`, but the active Plasma session does not yet include that group.

Only `ydotoold` needs access to `/dev/uinput`. The rest of the Plasma session does not need to be restarted. The `sg` command starts the daemon with the new group while preserving the current desktop session.

### Check for an existing daemon

```bash
ps -eo user,pid,cmd | grep '[y]dotoold'
```

If a daemon is already running as root, stop that specific process:

```bash
doas kill ROOT_DAEMON_PID
```

Replace `ROOT_DAEMON_PID` with the PID shown by the previous command.

Check the existing socket:

```bash
ls -l /run/user/"$(id -u)"/.ydotool_socket
```

If it is stale or owned by root, remove it:

```bash
doas rm -f /run/user/"$(id -u)"/.ydotool_socket
```

### Start the daemon with the new group

This command works from the existing session even though plain `id` does not yet list `input`:

```bash
mkdir -p ~/.cache

sg input -c 'exec /usr/bin/ydotoold' \
    > ~/.cache/ydotoold.log 2>&1 &

disown
```

The daemon is now detached from the terminal. Review its startup log:

```bash
cat ~/.cache/ydotoold.log
```

Expected output resembles:

```text
Socket path: /run/user/1000/.ydotool_socket
Socket permission: 0600
READY
```

This warning is harmless under Wayland:

```text
xinput command not found, not disabling mouse pointer acceleration
```

### Verify the temporary group

Find the daemon:

```bash
pgrep -a -u "$(id -u)" ydotoold
```

Confirm that its process has the `input` group:

```bash
PID="$(pgrep -n -u "$(id -u)" ydotoold)"
grep '^Groups:' "/proc/$PID/status"
getent group input
```

If `input` is group 97, the daemon's `Groups:` line should contain `97`.

The current shell's `id` output may still omit `input`. That is expected: `sg` granted the group only to `ydotoold`.

Focus a terminal and test keyboard injection:

```bash
ydotool type "temporary session test"
```

The text should be inserted at the prompt. The dictation shortcut can then be used for the rest of the current Plasma session. No logout is required.

> This is a bridge for the current session. Configure KDE Autostart so the daemon starts normally after the next login. Until that login, keep using the daemon started with `sg`.

---

## Step 9. Create the KDE Shortcut

Open:

```text
System Settings → Keyboard → Shortcuts
```

Add a new command or application shortcut with:

```text
Name: Voice Dictation
Command: /home/USERNAME/.local/bin/dictate-toggle
Shortcut: Meta+Space
```

Replace `USERNAME` with the actual username. KDE shortcut commands should use an absolute path rather than `~`.

Usage:

1. Focus a terminal or another text field.
2. Press `Meta+Space`.
3. Speak normally.
4. Pause briefly.
5. Press `Meta+Space` again.
6. The recognized text is typed at the cursor.

The Plasma tray microphone icon shows that `parec` opened the microphone. It does not show that the microphone delivered sound. A muted headset still produces the icon.

---

## Step 10. Start ydotoold Automatically

Create `~/.config/autostart/ydotoold.desktop`:

```bash
mkdir -p ~/.config/autostart
printf '%s\n' \
  '[Desktop Entry]' \
  'Type=Application' \
  'Name=ydotoold' \
  'Comment=Virtual keyboard daemon for offline dictation' \
  'Exec=/usr/bin/ydotoold' \
  'Terminal=false' \
  'X-KDE-autostart-phase=1' \
  > ~/.config/autostart/ydotoold.desktop
```

Do not put `doas`, `sudo`, or `sg` in this entry.

KDE does not process a newly created autostart entry until the next login. During the current non-fresh session, continue using the daemon started with `sg`.

At the next convenient Plasma logout and login:

1. The new Plasma session inherits the `input` group.
2. KDE starts `/usr/bin/ydotoold` as the desktop user.
3. The temporary `sg` workaround is no longer needed.

Verify after that login:

```bash
id
pgrep -a -u "$(id -u)" ydotoold
ls -l /run/user/"$(id -u)"/.ydotool_socket
ydotool type "autostart test"
```

Expected results:

- `id` lists `input`.
- `ydotoold` runs as the desktop user.
- The socket belongs to the desktop user.
- The focused window receives `autostart test`.

### Startup-path summary

| Situation | Command |
|---|---|
| Fresh login with `input` inherited | `ydotoold &` |
| Existing session without `input` inherited | `sg input -c 'exec /usr/bin/ydotoold' &` |
| Future Plasma logins | KDE runs `/usr/bin/ydotoold` through Autostart |

The existing-session method is safe to use until the next natural logout.

---

## Testing

### Test keyboard injection

Focus a terminal and run:

```bash
ydotool type "hello"
```

The word `hello` should be inserted at the prompt. Do not include a newline if the inserted text is not intended to be executed.

### Test the microphone

List available recording sources:

```bash
pactl get-default-source
pactl list short sources
```

Record five seconds of raw audio:

```bash
timeout 5 parec \
    --record \
    --rate=16000 \
    --channels=1 \
    --format=s16ne \
    > /tmp/microphone.raw
ls -lh /tmp/microphone.raw
```

A nonempty file indicates that audio data was captured.

### Test dictation

Focus a terminal, press `Meta+Space`, and say:

```text
this is a speech recognition test period
```

Press `Meta+Space` again. Expected output:

```text
this is a speech recognition test.
```

---

## Troubleshooting

### The microphone tray icon appears, but no text is typed

Check the log:

```bash
cat ~/.cache/dictate-toggle.log
```

If it contains:

```text
No text found in the audio
```

check:

- The physical headset mute button.
- KDE microphone mute.
- The default recording source.
- Whether the microphone produces a level in KDE Audio settings.

The Plasma tray icon only proves that `parec` opened the microphone.

### `ydotoold` reports permission denied

Example:

```text
failed to open uinput device: Permission denied
```

Check:

```bash
id
id "$USER"
ls -l /dev/uinput
grep '^input:' /etc/group
```

`/dev/uinput` should resemble:

```text
crw-rw---- root input /dev/uinput
```

If `id "$USER"` lists `input` but plain `id` does not, the account is configured and the current Plasma session is stale. Use [Step 8B](#step-8b-existing-plasma-session-without-logging-out) now. Use [Step 8A](#step-8a-fresh-plasma-login) when logging out is convenient.

### `ydotool type` hangs or types nothing

Check for a root-owned socket:

```bash
ls -l /run/user/"$(id -u)"/.ydotool_socket
```

Stop the root daemon, remove its stale socket, and restart the daemon as the desktop user. On a fresh session:

```bash
doas pkill ydotoold
rm -f /run/user/"$(id -u)"/.ydotool_socket
ydotoold &
disown
```

On an existing session that still lacks the `input` group, use `sg` as shown in Step 8B instead of the plain `ydotoold` command.

### The shortcut records but does not stop correctly

Remove stale dictation state and try the shortcut again:

```bash
rm -f /tmp/nerd-dictation.cookie
```

### The wrong microphone is selected

Find the desired source:

```bash
pactl list short sources
```

Set it as the default:

```bash
pactl set-default-source SOURCE_NAME
```

Alternatively, add this to the `begin` command in `dictate-toggle`:

```text
--pulse-device-name=SOURCE_NAME
```

### Spoken punctuation appears as words

Confirm that this file exists:

```bash
ls -l ~/.config/nerd-dictation/nerd-dictation.py
```

Check the dictation log for Python errors:

```bash
cat ~/.cache/dictate-toggle.log
```

---

## Security Notes

- `ydotoold` creates a virtual keyboard and can inject keystrokes into the focused application.
- The `input` group may have broad access to local input devices.
- Recognized terminal text is not automatically submitted because the punctuation configuration does not emit newlines.
- Always inspect dictated shell commands before pressing Enter.
- The recognizer runs locally, but any dictated text entered into a networked application is still transmitted by that application.

---

## References

- [nerd-dictation](https://github.com/ideasman42/nerd-dictation)
- [ydotool](https://github.com/ReimuNotMoe/ydotool)
- [Vosk API](https://alphacephei.com/vosk/)
- [Vosk Models](https://alphacephei.com/vosk/models)
- [Gentoo package: x11-misc/ydotool](https://packages.gentoo.org/packages/x11-misc/ydotool)
- [Gentoo Wiki: KDE](https://wiki.gentoo.org/wiki/KDE)
- [Gentoo Wiki: PipeWire](https://wiki.gentoo.org/wiki/PipeWire)
