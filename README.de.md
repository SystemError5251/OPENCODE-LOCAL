# OPENCODE-LOCAL – Kurzanleitung (Deutsch)

Ein KI-Coding-Assistent im Terminal, der komplett lokal und offline läuft: OpenCode als Oberfläche,
llama.cpp als Modell-Server. Keine Cloud, keine API-Keys, keine Telemetrie.
Ausführliche Doku (Englisch): [README.md](README.md).

## Installation

Internet wird nur einmal gebraucht: für die Installation und den Modell-Download.

### Termux (Android)
```bash
pkg install git
git clone https://github.com/systemerror5251/opencode-local.git && cd opencode-local
scripts/phase0-check.sh            # Gerätedaten prüfen
./install-termux.sh --dry-run      # zeigt nur, was passieren würde
./install-termux.sh --prebuilt-opencode   # offizielle OpenCode-Version (Prüfsumme fest); ohne die Option wird OpenCode aus dem Quellcode gebaut
scripts/fetch-model.sh qwen3-1.7b
scripts/bench.sh                   # Geschwindigkeit messen (Tokens/s)
mkdir -p ~/projects/meinprojekt && cd ~/projects/meinprojekt && opencode-local
```

### Linux
```bash
./install-linux.sh
scripts/fetch-model.sh qwen3-1.7b
cd ~/projects/meinprojekt && opencode-local
```

### Windows
```powershell
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1                # über WSL2 (empfohlen)
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -Mode Native   # ohne WSL
```

Danach das Netzwerk sperren, auf Android z. B. mit NetGuard oder RethinkDNS für Termux
(siehe [docs/security.md](docs/security.md#network-lock-down)).

## Bedienung

| Befehl | Wirkung |
|---|---|
| `opencode-local` | startet OpenCode im aktuellen Projektordner (Modell wird bei Bedarf gestartet) |
| `scripts/start-llama.sh --stop` | Modell-Server beenden (spart Akku) |
| `scripts/fetch-model.sh --list` | verfügbare Modelle anzeigen |
| `scripts/tunnel.sh user@pc` | größeres Modell auf dem PC im Heimnetz nutzen (SSH-Tunnel) |
| `scripts/tunnel.sh --stop` | zurück zum Modell auf dem Handy |
| `scripts/update.sh` | nur prüfen, ob es Updates gibt (ändert nichts) |
| `scripts/update.sh --apply` | Update holen und installieren |

## Sicherheit in Kürze

- Jede Dateiänderung und jeder Shell-Befehl muss von dir bestätigt werden.
- Löschen (`rm -r`), `sudo`, `curl`, `wget`, `ssh`, `git push` und Web-Zugriff sind gesperrt.
- Die KI sieht nur den Projektordner, in dem du `opencode-local` startest.
- Eigene Werkzeuge (MCP) löschen und überschreiben nie etwas:
  - **Papierkorb:** Dateien landen in `.trash/` und lassen sich zurückholen.
  - **Backup:** Sicherungen liegen außerhalb des Projekts.
  - **Verschlüsselung:** mit gpg; das Original bleibt erhalten.
  - **Video:** feste Voreinstellungen, nur lokale Dateien.
- **Wichtig:** Den Schlüssel `~/.local/share/opencode-local/keys/crypto.pass` (in Termux innerhalb von
  Debian) sichern. Ohne ihn lassen sich verschlüsselte Dateien nicht mehr öffnen.

## Grenzen

Kleine Handy-Modelle (1–3B) sind deutlich schwächer als Cloud-Modelle. Kleine Aufgaben stellen, oder
einen PC als Modell-Host nutzen (`scripts/tunnel.sh`).

Zum Prüfen nach der Installation: [docs/test-checklist.md](docs/test-checklist.md).
