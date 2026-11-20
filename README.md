# Autodarts Kiosk

Macht aus einem kleinen PC (getestet für **Dell OptiPlex 3070 Micro**) eine Autodarts-Maschine, die:

- beim Anlegen von Strom automatisch einschaltet,
- mit eigenem Boot-Logo und ohne Textausgabe startet,
- sich ohne Passwort anmeldet,
- direkt im Vollbild **play.autodarts.io** öffnet,
- den Autodarts Board-Client (Kameras) automatisch im Hintergrund startet und aktualisiert.

---

## 1. Betriebssystem: Debian 13 „Trixie“ (minimal, ohne Desktop)

Warum Debian und nicht Ubuntu?
Chromium ist unter Debian ein normales Paket (unter Ubuntu ein Snap, der im Kiosk-Modus Probleme macht). Ohne Desktop bleibt das System klein und startet schnell; der Kiosk läuft direkt über den schlanken Wayland-Compositor `cage`.

### 1.1 Was du brauchst

- USB-Stick (mind. 2 GB, wird gelöscht)
- Tastatur + Monitor am OptiPlex (nur für die Installation)
- Am besten **LAN-Kabel** (WLAN geht auch, ist aber umständlicher)

### 1.2 USB-Stick erstellen

1. **Debian netinst ISO (amd64)** herunterladen: <https://www.debian.org/download>
2. Auf den USB-Stick schreiben mit [balenaEtcher](https://etcher.balena.io/) (Windows/macOS/Linux) oder [Rufus](https://rufus.ie/) (Windows, Modus „DD-Image“).

### 1.3 BIOS vorbereiten (OptiPlex 3070)

Beim Einschalten **F2** drücken:

| Einstellung | Pfad | Wert |
|---|---|---|
| **Einschalten bei Strom** | Power Management → **AC Recovery** | **Power On** |
| SSD für Linux sichtbar machen | System Configuration → **SATA Operation** | **AHCI** (nicht „RAID On“) |
| Secure Boot | Secure Boot → Secure Boot Enable | **aus** (nur nötig, falls du später den UVC-Hack brauchst) |
| Schnellerer Start (optional) | POST Behavior → **Fastboot** | **Minimal** |

Speichern mit **Apply** → **Exit**.

> ⚠️ Steht SATA Operation auf „RAID On“, findet der Debian-Installer die NVMe-SSD nicht.

### 1.4 Debian installieren

USB-Stick einstecken, einschalten, **F12** drücken und den USB-Stick (UEFI) wählen.

1. **Install** (nicht „Graphical install“ – ist egal, Text geht schneller)
2. Sprache **Deutsch**, Standort **Deutschland**, Tastatur **Deutsch**
3. Rechnername: z. B. `autodarts` · Domain: leer lassen
4. **Root-Passwort: leer lassen** (zweimal Enter). Dann bekommt dein Benutzer automatisch `sudo`-Rechte.
5. Benutzer anlegen, z. B. Name `darts`, Benutzername `darts`, Passwort vergeben
6. Partitionierung: **Geführt – vollständige Festplatte verwenden** → SSD wählen → **Alle Dateien auf eine Partition** → Änderungen schreiben: **Ja**
7. Paketmanager-Spiegel: **Deutschland** → `deb.debian.org`
8. **Softwareauswahl – wichtig!** Mit Leertaste alles abwählen bis auf:
   - `[*] SSH server`
   - `[*] Standard-Systemwerkzeuge`

   Also **kein** „Debian desktop environment“, **kein** GNOME/KDE/Xfce usw.
9. Installation fertigstellen, USB-Stick abziehen, neu starten.

Danach landest du an einer schwarzen Konsole und meldest dich mit deinem Benutzer an.

> 💡 Ab hier kannst du auch bequem vom Laptop aus weitermachen:
> `ssh darts@<IP>` (die IP zeigt `hostname -I` am OptiPlex an). Nach dem Skript geht auch `ssh darts@autodarts.local`.

---

## 2. Autodarts-Kiosk installieren

Am OptiPlex (oder per SSH):

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/yannicschuller/autodarts.git
cd autodarts
sudo ./install.sh
sudo reboot
```

> Falls das Repo privat ist, fragt `git clone` nach Benutzername und einem
> [GitHub-Token](https://github.com/settings/tokens) als Passwort. Alternativ den Ordner per USB-Stick kopieren.

Das Skript erledigt:

| Schritt | Was passiert |
|---|---|
| Pakete | `cage`, `chromium`, `plymouth`, Audio (`pipewire`), Intel-Firmware, Sicherheitsupdates |
| Autodarts | offizieller Installer (`get.autodarts.io`) inkl. Autostart- und Update-Dienst |
| Autologin | `tty1` meldet den Benutzer ohne Passwort an |
| Kiosk | Chromium im Vollbild mit play.autodarts.io, startet nach Absturz automatisch neu |
| Boot-Logo | eigenes Plymouth-Theme mit `assets/logo.png`, kein GRUB-Menü, keine Textausgabe |
| Energie | kein Standby, Power-Taste fährt sauber herunter |

### Optionen

```bash
# eigenes Logo verwenden (PNG, am besten mit transparentem oder schwarzem Hintergrund)
sudo LOGO=/pfad/zu/meinlogo.png ./install.sh

# andere Startseite
sudo KIOSK_URL=https://play.autodarts.io ./install.sh

# nur Kiosk, ohne Autodarts Board-Client
sudo SKIP_AUTODARTS=1 ./install.sh
```

Das Skript kann jederzeit erneut ausgeführt werden, z. B. nach einem Logo-Wechsel.

---

## 3. Nach dem ersten Neustart

1. **Board einrichten:** Von einem anderen Gerät im selben Netzwerk den Board Manager öffnen:
   `http://<IP-des-OptiPlex>:3180` → Kameras kalibrieren und das Board mit deinem Autodarts-Konto verbinden.
2. **Im Kiosk anmelden:** Einmalig mit Tastatur bei play.autodarts.io einloggen. Die Anmeldung bleibt gespeichert.
3. **Test:** Stecker ziehen, wieder einstecken → PC startet von selbst bis in den Vollbild-Kiosk.

---

## Bedienung & Fehlersuche

| Aktion | Befehl / Taste |
|---|---|
| Konsole öffnen (Kiosk läuft weiter) | **Strg + Alt + F2** · zurück mit **Strg + Alt + F1** |
| Kiosk vorübergehend deaktivieren | `touch ~/.no-kiosk` und neu starten (wieder aktivieren: `rm ~/.no-kiosk`) |
| Log des Board-Clients | `journalctl -u autodarts -f` |
| Board-Client neu starten | `sudo systemctl restart autodarts` |
| Log des Kiosks | `cat /tmp/autodarts-kiosk.log` |
| Ausschalten | Power-Taste kurz drücken (fährt sauber herunter) |

**Hinweise**

- Das **Dell-Logo** beim Einschalten kommt aus dem BIOS und lässt sich nicht ersetzen. Mit *Fastboot → Minimal* ist es nur kurz zu sehen; danach erscheint dein eigenes Logo.
- Die drei Kameras möglichst auf **verschiedene USB-Ports** verteilen (nicht alle über einen Hub).
- Hartes Abschalten über den Strom ist meistens kein Problem, sauberer ist aber die Power-Taste.
