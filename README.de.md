# OPENCODE-LOCAL – Kurzanleitung (Deutsch)

Ein KI-Coding-Assistent im Terminal, der komplett lokal und offline läuft: OpenCode als Oberfläche,
llama.cpp als Modell-Server. Keine Cloud, keine API-Keys, keine Telemetrie.
Ausführliche Doku (Englisch): [README.md](README.md).

## Installation

Internet wird nur einmal gebraucht: für die Installation und den Modell-Download (etwa 2 GB).
Jeden Block so kopieren, wie er ist; jede Zeile darf auch ein zweites Mal laufen.

### Termux (Android)

Termux aus F-Droid oder von GitHub installieren (die Play-Store-Version ist veraltet), dann:

```bash
pkg install -y git
git clone https://github.com/SystemError5251/OPENCODE-LOCAL.git ~/opencode-local || git -C ~/opencode-local pull
cd ~/opencode-local
./quickstart.sh
```

`quickstart.sh` baut llama.cpp in Termux (dauert 10–20 Minuten), richtet Debian mit der offiziellen
OpenCode-Version ein (Prüfsumme wird kontrolliert), lädt ein Modell passend zum RAM und zeigt den nächsten
Schritt. Danach OpenCode in einem Projektordner starten:

```bash
mkdir -p ~/projects/meinprojekt && cd ~/projects/meinprojekt && opencode-local
```

### Linux (und WSL2)

```bash
sudo apt-get install -y git     # oder dnf / pacman
git clone https://github.com/SystemError5251/OPENCODE-LOCAL.git ~/opencode-local || git -C ~/opencode-local pull
cd ~/opencode-local
./quickstart.sh
mkdir -p ~/projects/meinprojekt && cd ~/projects/meinprojekt && opencode-local
```
Falls `quickstart.sh` eine Zeile `export PATH=...` ausgibt: ausführen und in `~/.bashrc` eintragen.

### Windows
Am besten WSL2 und dort die Linux-Schritte. Ohne WSL, in PowerShell:
```powershell
git clone https://github.com/SystemError5251/OPENCODE-LOCAL.git $HOME\opencode-local
cd $HOME\opencode-local
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -Mode Native -FetchModel qwen3-1.7b
```

### Gut zu wissen

- Anderes Modell: `./quickstart.sh --model qwen3-4b` (Liste: `scripts/fetch-model.sh --list`).
- OpenCode startet im **lite**-Modus: nur die Grundwerkzeuge (lesen, suchen, Shell, schreiben, ersetzen).
  So gehen pro Schritt etwa 2.900 statt 7.000 Tokens an das Modell, die erste Antwort dauert auf dem Handy
  etwa eine Minute statt zwei. Mit **Tab** wechselst du zum vollen **coder**-Agenten (Backups, Papierkorb,
  Verschlüsselung, Video). Einfache Dinge wie einen Ordner anlegen gehen in der normalen Shell schneller.
- Der Modell-Server beendet sich 10 Minuten nach der letzten Sitzung von selbst (RAM frei, Handy kann
  schlafen). Andere Zeit: `OCL_LLAMA_IDLE_MIN=30`, nie beenden: `OCL_LLAMA_IDLE_MIN=0`.
- Fehlermeldung `No such file or directory`: du bist nicht im Repo-Ordner, also erst `cd ~/opencode-local`.
- Abgebrochene Installation: einfach `./quickstart.sh` noch einmal starten.

Danach das Netzwerk sperren, auf Android z. B. mit NetGuard oder RethinkDNS für Termux
(siehe [docs/security.md](docs/security.md#network-lock-down)).

## Bedienung

| Befehl | Wirkung |
|---|---|
| `opencode-local` | startet OpenCode im aktuellen Projektordner (Modell wird bei Bedarf gestartet) |
| `scripts/start-llama.sh --stop` | Modell-Server sofort beenden (passiert sonst nach 10 Minuten von selbst) |
| `opencode-local --agent coder` | gleich mit dem vollen Agenten starten (oder Tab in OpenCode) |
| `scripts/fetch-model.sh --list` | verfügbare Modelle anzeigen |
| `scripts/tunnel.sh user@pc` | größeres Modell auf dem PC im Heimnetz nutzen (SSH-Tunnel) |
| `scripts/tunnel.sh --stop` | zurück zum Modell auf dem Handy |
| `scripts/update.sh` | nur prüfen, ob es Updates gibt (ändert nichts) |
| `scripts/update.sh --apply` | Update holen und installieren |
| `scripts/wipe-sessions.sh` | alte Sitzungsdaten und Logs früherer Versionen löschen |

## Sicherheit in Kürze

- Jede Dateiänderung und jeder Shell-Befehl muss von dir bestätigt werden.
- Löschen (`rm -r`), `sudo`, `curl`, `wget`, `ssh`, `git push` und Web-Zugriff sind gesperrt.
- Die KI sieht nur den Projektordner, in dem du `opencode-local` startest.
- Kein Verlauf, keine Logs: Jede Sitzung (Nachrichten, Snapshots, Logs, Cache, temporäre Dateien) liegt in
  einem privaten Temp-Ordner, möglichst im RAM, und wird beim Beenden von OpenCode gelöscht.
  Alte Daten aus früheren Versionen löscht einmalig `scripts/wipe-sessions.sh`.
- Eigene Werkzeuge (MCP) löschen und überschreiben nie etwas:
  - **Papierkorb:** Dateien landen in `.trash/` und lassen sich zurückholen.
  - **Backup:** Sicherungen liegen außerhalb des Projekts.
  - **Verschlüsselung:** mit gpg; das Original bleibt erhalten.
  - **Video:** feste Voreinstellungen, nur lokale Dateien.
- **Wichtig:** Den Schlüssel `~/.local/share/opencode-local/keys/crypto.pass` (in Termux innerhalb von
  Debian) sichern. Ohne ihn lassen sich verschlüsselte Dateien nicht mehr öffnen.

## Grenzen

Kleine Handy-Modelle (1–4B) sind deutlich schwächer als Cloud-Modelle. Kleine Aufgaben stellen, oder
einen PC als Modell-Host nutzen (`scripts/tunnel.sh`).

Zum Prüfen nach der Installation: [docs/test-checklist.md](docs/test-checklist.md).
