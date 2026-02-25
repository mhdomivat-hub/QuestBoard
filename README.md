# QuestBoard Setup

QuestBoard besteht aus:
- Caddy als Reverse Proxy
- Vapor API (Swift)
- Next.js Web-Frontend
- PostgreSQL

## Projektstruktur

- docker-compose.yml
- Caddyfile / Caddyfile.example
- api/ (Vapor)
- web/ (Next.js)
- scripts/install-server.sh (Linux/Hetzner Bootstrap)
- scripts/smoke-test.ps1 (E2E Smoke-Test)

## Schnellstart lokal

1. .env.example nach .env kopieren und Werte setzen.
2. Stack starten:

~~~bash
docker compose up -d --build
~~~

3. Status/Logs pruefen:

~~~bash
docker compose ps
docker compose logs -f --tail=200
~~~

## Server-Installation (frischer Hetzner Linux Host)

Voraussetzung: Ubuntu/Debian-basierter Host mit Root-Rechten.

1. Repo auf den Server klonen (empfohlen nach /opt/questboard):

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
- .env aus .env.example erzeugen (falls nicht vorhanden)
- Caddyfile vorbereiten (optional domain-basiert)
- Images bauen
- Container starten (docker compose up -d)

### Wichtige Nacharbeit auf Server

Bearbeite danach unbedingt /opt/questboard/.env:
- POSTGRES_PASSWORD
- BOOTSTRAP_ADMIN_USERNAME
- BOOTSTRAP_ADMIN_PASSWORD
- APP_BASE_URL

Danach neu starten:

~~~bash
docker compose -f /opt/questboard/docker-compose.yml up -d --build
~~~

## Smoke-Test

scripts/smoke-test.ps1 deckt End-to-End ab, inklusive:
- Auth/Login/Logout
- Quest/Requirement/Contribution Flows
- RBAC-/Negative-Cases
- Admin Retention
- Admin Export/Import (inkl. chunked/split Validierung und Dedupe)

Beispiel:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\smoke-test.ps1
~~~

Mit expliziten Credentials:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\smoke-test.ps1 -BaseUrl http://localhost -Username Admin -Password 'Admin'
~~~
