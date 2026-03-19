# QuestBoard Setup

QuestBoard besteht aus:
- Caddy als Reverse Proxy
- Vapor API (Swift)
- Next.js Web-Frontend
- PostgreSQL

## Projektstruktur

- `docker-compose.yml`
- `docker-compose.ghcr.yml`
- `Caddyfile` / `Caddyfile.example`
- `api/` (Vapor)
- `web/` (Next.js)
- `scripts/install-server.sh` (Linux/Hetzner Bootstrap)
- `scripts/deploy-ghcr.sh` (Server-Deploy fuer GHCR)
- `scripts/publish-ghcr.ps1` (lokaler GHCR-Publish)
- `scripts/smoke-test.ps1` (E2E Smoke-Test)

## Schnellstart lokal

1. `.env.example` nach `.env` kopieren und Werte setzen.
2. Stack starten:

~~~bash
docker compose up -d --build
~~~

3. Status/Logs pruefen:

~~~bash
docker compose ps
docker compose logs -f --tail=200
~~~

## Alternative: GHCR statt Server-Build

Der aktuelle Standard bleibt unveraendert:

~~~bash
docker compose up -d --build
~~~

Zusaetzlich gibt es einen separaten Registry-basierten Weg ueber GHCR. Damit kannst du lokal bauen, die Images nach GitHub Container Registry pushen und auf dem Server nur noch ziehen.

Wichtig:
- Diese Alternative gefaehrdet den aktuellen Weg nicht.
- `docker-compose.yml` bleibt der bisherige Build-Flow.
- `docker-compose.ghcr.yml` ist der neue Pull-Flow.
- Dein SSH-Key fuer GitHub hilft beim Repo-Klonen, aber fuer GHCR brauchst du trotzdem ein GitHub-Token.

### Voraussetzungen fuer GHCR

Du brauchst ein GitHub Token mit mindestens:
- `write:packages` zum Pushen von Images
- `read:packages` zum Ziehen von Images

Bei privaten Images braucht auch der Server Zugriff auf `read:packages`.

### Lokal nach GHCR veroeffentlichen

1. Token in der aktuellen Shell setzen:

~~~powershell
$env:GHCR_TOKEN="DEIN_GITHUB_TOKEN"
~~~

2. Images lokal bauen und pushen:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\publish-ghcr.ps1 -Tag v0.1.0
~~~

Optional mit anderem Namespace oder ohne erneuten Build:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\publish-ghcr.ps1 -Namespace mhdomivat-hub -Username mhdomivat-hub -Tag v0.1.0
powershell -ExecutionPolicy Bypass -File .\scripts\publish-ghcr.ps1 -Tag v0.1.0 -SkipBuild
~~~

Das Skript:
- meldet dich bei `ghcr.io` an
- baut `api` und `web` lokal
- pusht beide Images

### Server auf GHCR-Deployment umstellen

1. `.env` auf dem Server ergaenzen:

~~~env
GHCR_NAMESPACE=mhdomivat-hub
GHCR_IMAGE_TAG=v0.1.0
~~~

2. Optional einmalig bei GHCR anmelden:

~~~bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u mhdomivat-hub --password-stdin
~~~

3. GHCR-Compose verwenden:

~~~bash
docker compose -f docker-compose.ghcr.yml pull
docker compose -f docker-compose.ghcr.yml up -d
~~~

Oder mit dem Hilfsskript:

~~~bash
chmod +x scripts/deploy-ghcr.sh
GHCR_TOKEN=DEIN_GITHUB_TOKEN GHCR_IMAGE_TAG=v0.1.0 bash scripts/deploy-ghcr.sh
~~~

### Zurueck auf den bisherigen Weg

Jederzeit moeglich, weil die Loesungen getrennt sind:

~~~bash
docker compose -f docker-compose.yml up -d --build
~~~

## Server-Installation (frischer Hetzner Linux Host)

Voraussetzung: Ubuntu/Debian-basierter Host mit Root-Rechten.

1. Repo auf den Server klonen (empfohlen nach `/opt/questboard`):

~~~bash
sudo mkdir -p /opt
cd /opt
sudo git clone <REPO_URL> questboard
cd /opt/questboard
~~~

2. Install-Skript ausfuehrbar machen:

~~~bash
sudo chmod +x scripts/install-server.sh
~~~

3. Install-Skript starten:

~~~bash
sudo bash scripts/install-server.sh
~~~

Optional mit Domain-Caddyfile:

~~~bash
sudo DOMAIN=quest.example.com EMAIL=admin@example.com bash scripts/install-server.sh
~~~

Das Skript erledigt:
- Docker Engine + Docker Compose Plugin installieren
- `.env` aus `.env.example` erzeugen (falls nicht vorhanden)
- `Caddyfile` vorbereiten (optional domain-basiert)
- Images bauen
- Container starten (`docker compose up -d`)

### Wichtige Nacharbeit auf Server

Bearbeite danach unbedingt `/opt/questboard/.env`:
- `POSTGRES_PASSWORD`
- `BOOTSTRAP_ADMIN_USERNAME`
- `BOOTSTRAP_ADMIN_PASSWORD`
- `APP_BASE_URL`

Danach neu starten:

~~~bash
docker compose -f /opt/questboard/docker-compose.yml up -d --build
~~~

## Welche Loesung wann?

- `docker-compose.yml`
  - aktuelle Standardloesung
  - baut `api` und `web` direkt auf dem Zielsystem

- `docker-compose.ghcr.yml`
  - alternative Release-Loesung
  - Images werden lokal oder in CI gebaut
  - Server zieht nur fertige Images

Wenn dein lokaler Build 2 bis 3 Minuten braucht und der Server 10 Minuten, ist `docker-compose.ghcr.yml` meist der bessere Release-Weg.

## Smoke-Test

`scripts/smoke-test.ps1` deckt End-to-End ab, inklusive:
- Auth/Login/Logout
- Quest/Requirement/Contribution Flows
- RBAC-/Negative-Cases
- Admin Retention
- Admin Export/Import / Data Transfer
- Blueprints / Storage / Quest Templates

Beispiel:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\smoke-test.ps1
~~~

Mit expliziten Credentials:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\smoke-test.ps1 -BaseUrl http://localhost -Username Admin -Password 'Admin'
~~~
