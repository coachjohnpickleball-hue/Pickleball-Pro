# Pickleball Pro Technical Blueprint

## Product Vision

Pickleball Pro is a SaaS platform for pickleball clubs, coaches, leagues, and tournament organizers.

The goal is to support many clubs from one shared application while keeping each club's data isolated and secure.

## Core Architecture

- Frontend: Web app / PWA
- Backend: Cloudflare Workers
- Database: Cloudflare D1
- Hosting: Cloudflare
- Authentication: Cloudflare Access or app-based login
- Repository: GitHub
- Deployment: GitHub to Cloudflare

## Environments

### Production
Branch: main

Stable customer-facing version.

### Development
Branch: develop

Used for testing and integration.

### Feature Branches
Pattern: feature/name

Used for isolated feature development.

## Multi-Tenant Model

Each club is a tenant.

Every major record should include:

- club_id
- created_at
- updated_at where needed
- status where needed

This ensures one club cannot access another club's data.

## Primary Entities

- clubs
- users
- club_users
- players
- tournaments
- leagues
- sessions
- matches
- scores
- ratings
- subscriptions
- audit_logs

## Roles

### owner
Full control of a club account.

### admin
Manages club setup, users, tournaments, and players.

### coach
Creates schedules, manages players, records results.

### scorekeeper
Records scores only.

### player
Views schedules, results, and standings.

## Data Isolation Rules

All API requests must resolve the active club first.

Users can only access clubs where they have a valid club_users record.

No query should return club data without filtering by club_id.

## API Design

Recommended pattern:

- GET /api/clubs
- GET /api/clubs/:clubId
- GET /api/clubs/:clubId/players
- POST /api/clubs/:clubId/players
- GET /api/clubs/:clubId/tournaments
- POST /api/clubs/:clubId/tournaments
- GET /api/clubs/:clubId/matches
- POST /api/clubs/:clubId/scores

## Security Principles

- Never expose private data across clubs
- Validate all inputs
- Check user role before writes
- Log important actions
- Keep secrets out of GitHub
- Use environment variables for API keys
- Never commit node_modules
- Never commit SSH keys or .env files

## Billing / Licensing

Plans may include:

### Starter
Basic tournaments and player management.

### Club
Multiple events, advanced standings, club branding.

### Pro Club
Leagues, notifications, analytics, multi-location support.

### Enterprise
Custom domains, integrations, premium support.

## Cloudflare Deployment

Recommended setup:

- main deploys to production
- develop deploys to staging
- feature branches are tested locally or in preview

## Database Migration Strategy

Database schema changes should be stored in:

database/migrations/

Each migration should be named with an order prefix:

001_initial_schema.sql
002_add_leagues.sql
003_add_billing.sql

## Release Workflow

1. Create feature branch from develop
2. Build and test feature
3. Commit changes
4. Push branch
5. Open pull request into develop
6. Test staging
7. Merge develop into main
8. Tag release

Example tags:

v1.0.0
v1.1.0
v1.2.0

## Coding Standards

- Keep business logic separate from UI logic
- Keep scheduling rules easy to test
- Use clear function names
- Avoid large files where possible
- Document important decisions
- Prefer small commits with clear messages

## Immediate Roadmap

### Phase 1
- Clean GitHub repo
- Branching model
- Architecture documents
- Initial database schema

### Phase 2
- Cloudflare staging
- Cloudflare production
- D1 database setup
- Authentication model

### Phase 3
- Club management portal
- Tenant-aware players
- Tenant-aware tournaments
- Tenant-aware matches

### Phase 4
- Licensing and plans
- Payments
- Email/SMS notifications
- Club branding

### Phase 5
- AI scheduling assistant
- Analytics
- Rating trends
- Fairness reports
