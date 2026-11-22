#!/usr/bin/env bash
# =============================================================================
#  Autodarts Kiosk – Komplett-Installer
#
#  Macht aus einer frischen Debian-13-Minimalinstallation (ohne Desktop)
#  eine Autodarts-Kiosk-Maschine:
#    1. Autodarts Board-Client (offizieller Installer, inkl. Autostart + Updater)
#    2. Automatische Anmeldung ohne Passwort auf tty1
#    3. Vollbild-Kiosk (cage + Chromium) mit play.autodarts.io
#    4. Eigenes Boot-Logo (Plymouth) und stiller Bootvorgang ohne GRUB-Menü
#    5. Kein Standby / Bildschirmschoner, Power-Taste fährt sauber herunter
#
#  Aufruf (als normaler Benutzer, NICHT als root einloggen):
#      sudo ./install.sh
#
#  Optionen über Umgebungsvariablen:
#      KIOSK_URL=...        Startseite          (Standard: https://play.autodarts.io)
#      LOGO=/pfad/logo.png  Eigenes Boot-Logo   (Standard: assets/logo.png)
#      SKIP_AUTODARTS=1     Board-Client nicht installieren
#
#  Das Skript kann gefahrlos mehrfach ausgeführt werden.
# =============================================================================
set -euo pipefail

KIOSK_URL="${KIOSK_URL:-https://play.autodarts.io}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
LOGO="${LOGO:-$SCRIPT_DIR/assets/logo.png}"
LOGO_FALLBACK_URL="https://raw.githubusercontent.com/yannicschuller/autodarts/main/assets/logo.png"
THEME_NAME="autodarts-kiosk"

c_info()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
c_ok()    { printf '\033[1;32m    ✓ %s\033[0m\n' "$*"; }
c_warn()  { printf '\033[1;33m    ! %s\033[0m\n' "$*"; }
die()     { printf '\033[1;31mFEHLER: %s\033[0m\n' "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# 0. Vorprüfungen
# -----------------------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "Bitte mit sudo starten:  sudo ./install.sh"

KIOSK_USER="${KIOSK_USER:-${SUDO_USER:-}}"
[[ -n "$KIOSK_USER" && "$KIOSK_USER" != "root" ]] \
  || die "Bitte als normaler Benutzer mit sudo ausführen (nicht direkt als root)."
id "$KIOSK_USER" &>/dev/null || die "Benutzer '$KIOSK_USER' existiert nicht."
KIOSK_HOME="$(getent passwd "$KIOSK_USER" | cut -d: -f6)"

if ! grep -qi '^ID=debian' /etc/os-release; then
  c_warn "Getestet für Debian 13. Dieses System ist kein Debian – weiter auf eigenes Risiko."
fi

c_info "Installiere Autodarts-Kiosk für Benutzer '$KIOSK_USER' → $KIOSK_URL"

# -----------------------------------------------------------------------------
# 1. Pakete
# -----------------------------------------------------------------------------
c_info "Pakete installieren"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  curl ca-certificates \
  cage chromium \
  plymouth plymouth-themes \
  pipewire pipewire-pulse wireplumber \
  fonts-dejavu-core avahi-daemon network-manager \
  unattended-upgrades
# Firmware für Intel-GPU und Qualcomm/Atheros-WLAN (liegt in non-free-firmware)
for fw in firmware-misc-nonfree firmware-atheros; do
  apt-get install -y "$fw" 2>/dev/null \
    || c_warn "$fw nicht verfügbar – nicht schlimm."
done
c_ok "Pakete installiert"

# Benutzer braucht Zugriff auf GPU, Kameras und Audio
usermod -aG video,render,audio,input "$KIOSK_USER" 2>/dev/null || true

# -----------------------------------------------------------------------------
# 2. Autodarts Board-Client
# -----------------------------------------------------------------------------
if [[ "${SKIP_AUTODARTS:-0}" != "1" ]]; then
  c_info "Autodarts Board-Client installieren (offizieller Installer)"
  # Läuft als der Kiosk-Benutzer, damit der Dienst nicht als root läuft.
  sudo -u "$KIOSK_USER" -H bash -c 'bash <(curl -sL https://get.autodarts.io)'
  systemctl enable autodarts.service 2>/dev/null || true
  c_ok "Autodarts installiert (Board Manager: http://<IP-des-PCs>:3180)"
else
  c_warn "Autodarts-Installation übersprungen (SKIP_AUTODARTS=1)"
fi

# -----------------------------------------------------------------------------
# 3. Kiosk-Startskript
# -----------------------------------------------------------------------------
c_info "Kiosk einrichten"
cat > /usr/local/bin/autodarts-kiosk <<EOF
#!/usr/bin/env bash
# Startet Chromium im Vollbild unter cage (Wayland-Kiosk-Compositor).
URL="\${KIOSK_URL:-$KIOSK_URL}"

# Bis zu 60 s auf Internet warten, sonst zeigt Chromium eine Fehlerseite
for _ in \$(seq 1 60); do
  curl -s --max-time 2 -o /dev/null "\$URL" && break
  sleep 1
done

# "Chromium wurde nicht korrekt beendet"-Hinweis nach Stromausfall unterdrücken
PREFS="\$HOME/.config/chromium/Default/Preferences"
if [[ -f "\$PREFS" ]]; then
  sed -i 's/"exited_cleanly":false/"exited_cleanly":true/; s/"exit_type":"[^"]*"/"exit_type":"Normal"/' "\$PREFS"
fi

exec cage -s -- chromium \\
  --kiosk "\$URL" \\
  --ozone-platform=wayland \\
  --no-first-run \\
  --noerrdialogs \\
  --disable-infobars \\
  --disable-session-crashed-bubble \\
  --disable-features=Translate,TranslateUI \\
  --password-store=basic \\
  --autoplay-policy=no-user-gesture-required \\
  --check-for-update-interval=31536000 \\
  --overscroll-history-navigation=0
EOF
chmod 755 /usr/local/bin/autodarts-kiosk
c_ok "/usr/local/bin/autodarts-kiosk"

# Kiosk beim Login auf tty1 starten (in Endlosschleife, falls Chromium abstürzt).
# Notausgang: Datei ~/.no-kiosk anlegen, dann bleibt tty1 eine normale Konsole.
PROFILE="$KIOSK_HOME/.bash_profile"
MARK_BEGIN="# >>> autodarts-kiosk >>>"
MARK_END="# <<< autodarts-kiosk <<<"
touch "$PROFILE"
sed -i "/$MARK_BEGIN/,/$MARK_END/d" "$PROFILE"
cat >> "$PROFILE" <<EOF
$MARK_BEGIN
[[ -f ~/.profile ]] && . ~/.profile
if [[ -z "\${WAYLAND_DISPLAY:-}" && "\$(tty)" == "/dev/tty1" && ! -f ~/.no-kiosk ]]; then
  while true; do
    /usr/local/bin/autodarts-kiosk >/tmp/autodarts-kiosk.log 2>&1
    sleep 2
  done
fi
$MARK_END
EOF
touch "$KIOSK_HOME/.hushlogin"
chown "$KIOSK_USER:" "$PROFILE" "$KIOSK_HOME/.hushlogin"
c_ok "Kiosk startet automatisch auf tty1"

# -----------------------------------------------------------------------------
# 4. Automatische Anmeldung (ohne Passwort) auf tty1
# -----------------------------------------------------------------------------
c_info "Automatische Anmeldung einrichten"
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear --noissue %I \$TERM
EOF
systemctl daemon-reload
c_ok "Autologin für '$KIOSK_USER' auf tty1"

# -----------------------------------------------------------------------------
# 5. Kein Standby, Power-Taste = sauber herunterfahren
# -----------------------------------------------------------------------------
c_info "Energieverwaltung"
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/autodarts-kiosk.conf <<'EOF'
[Login]
HandlePowerKey=poweroff
IdleAction=ignore
EOF
c_ok "Standby deaktiviert"

# -----------------------------------------------------------------------------
# 6. Boot-Logo (Plymouth) + stiller Boot
# -----------------------------------------------------------------------------
c_info "Boot-Logo einrichten"
if [[ ! -f "$LOGO" ]]; then
  c_warn "Kein Logo unter $LOGO – lade Standard-Logo aus dem Repo"
  LOGO="/tmp/autodarts-logo.png"
  curl -fsSL "$LOGO_FALLBACK_URL" -o "$LOGO" || LOGO=""
fi

if [[ -n "$LOGO" ]]; then
  THEME_DIR="/usr/share/plymouth/themes/$THEME_NAME"
  mkdir -p "$THEME_DIR"
  install -m 644 "$LOGO" "$THEME_DIR/logo.png"

  cat > "$THEME_DIR/$THEME_NAME.plymouth" <<EOF
[Plymouth Theme]
Name=Autodarts Kiosk
Description=Schwarzer Hintergrund mit zentriertem Logo
ModuleName=script

[script]
ImageDir=$THEME_DIR
ScriptFile=$THEME_DIR/$THEME_NAME.script
EOF

  cat > "$THEME_DIR/$THEME_NAME.script" <<'EOF'
Window.SetBackgroundTopColor(0, 0, 0);
Window.SetBackgroundBottomColor(0, 0, 0);

logo.image = Image("logo.png");
# Logo verkleinern, falls es größer als 60 % des Bildschirms ist
max_w = Window.GetWidth() * 0.6;
max_h = Window.GetHeight() * 0.6;
if (logo.image.GetWidth() > max_w || logo.image.GetHeight() > max_h) {
  f = Math.Min(max_w / logo.image.GetWidth(), max_h / logo.image.GetHeight());
  logo.image = logo.image.Scale(logo.image.GetWidth() * f, logo.image.GetHeight() * f);
}
logo.sprite = Sprite(logo.image);
logo.sprite.SetX(Window.GetX() + Window.GetWidth()  / 2 - logo.image.GetWidth()  / 2);
logo.sprite.SetY(Window.GetY() + Window.GetHeight() / 2 - logo.image.GetHeight() / 2);
EOF

  # Intel-Grafiktreiber früh laden, damit das Logo schon ganz am Anfang erscheint
  grep -qx 'i915' /etc/initramfs-tools/modules 2>/dev/null || echo 'i915' >> /etc/initramfs-tools/modules

  plymouth-set-default-theme "$THEME_NAME"
  c_ok "Plymouth-Theme '$THEME_NAME' gesetzt"
else
  c_warn "Kein Logo verfügbar – Boot-Logo übersprungen"
fi

# GRUB: kein Menü, keine Textausgabe
c_info "Bootvorgang still schalten"
GRUB_FILE=/etc/default/grub
if [[ -f "$GRUB_FILE" ]]; then
  set_grub() {
    if grep -q "^$1=" "$GRUB_FILE"; then
      sed -i "s|^$1=.*|$1=$2|" "$GRUB_FILE"
    else
      echo "$1=$2" >> "$GRUB_FILE"
    fi
  }
  set_grub GRUB_TIMEOUT 0
  set_grub GRUB_TIMEOUT_STYLE hidden
  set_grub GRUB_CMDLINE_LINUX_DEFAULT '"quiet splash loglevel=3 rd.udev.log_level=3 systemd.show_status=false rd.systemd.show_status=false vt.global_cursor_default=0 consoleblank=0"'
  set_grub GRUB_DISABLE_OS_PROBER true
  update-grub
  c_ok "GRUB angepasst"
else
  c_warn "/etc/default/grub nicht gefunden – GRUB nicht angepasst"
fi

update-initramfs -u
c_ok "initramfs neu gebaut"

# -----------------------------------------------------------------------------
# 7. Automatische Sicherheitsupdates
# -----------------------------------------------------------------------------
c_info "Automatische Sicherheitsupdates"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
c_ok "unattended-upgrades aktiv"

# -----------------------------------------------------------------------------
# Fertig
# -----------------------------------------------------------------------------
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
cat <<EOF

$(printf '\033[1;32m')====================================================================
  Fertig! Bitte neu starten:   sudo reboot
====================================================================$(printf '\033[0m')

Noch von Hand zu erledigen:

  1. BIOS: Einschalten bei Stromzufuhr
     Beim Start F2 drücken →  Power → Power Failure Recovery → "Always On"
     (Optional: Boot → Fast Boot → "Enabled" für schnelleren Start)

  2. Board einrichten
     Board Manager von einem anderen Gerät öffnen:  http://${IP:-<IP-des-PCs>}:3180
     Kameras kalibrieren und das Board mit deinem Autodarts-Konto verbinden.

  3. Im Kiosk einmalig bei play.autodarts.io anmelden (Tastatur anschließen).
     Die Anmeldung bleibt danach gespeichert.

Nützlich:
  • Strg+Alt+F2       → Konsole (Kiosk läuft auf F1 weiter)
  • touch ~/.no-kiosk → Kiosk beim nächsten Start nicht starten
  • journalctl -u autodarts -f   → Log vom Board-Client
EOF
