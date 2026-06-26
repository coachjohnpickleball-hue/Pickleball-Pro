# Pickleball Pro 1.0 Architecture Plan

## Goal

Prepare Pickleball Pro for a commercial 1.0 release by separating the application into clear layers.

## Layers

### app
Frontend user interface.

### worker
Cloudflare Worker API.

### services
Business logic such as scheduling, standings, ratings, fairness, and permissions.

### data
Database access layer.

### infrastructure
Cloudflare, deployment, environment, and setup files.

### tests
Automated tests.

## Key Rule

The scheduler should not depend directly on the UI.

The UI should call services or APIs.

The services should call the data layer.

## Target Flow

User Interface
→ API / Worker
→ Services
→ Data Layer
→ Database

## First 1.0 Priorities

1. Keep current app working.
2. Identify current scheduler code.
3. Move scheduler logic into services.
4. Add tests around scheduler behavior.
5. Prepare Cloudflare D1 integration.
6. Add tenant-aware club_id filtering.
7. Prepare staging and production deployment.

## Do Not Break

- Completed rounds must remain immutable.
- Scored matches must not be deleted by regeneration.
- Draft round regeneration must not affect completed rounds.
- Existing tournament workflow must keep working.
