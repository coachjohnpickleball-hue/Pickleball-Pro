# Pickleball Pro Architecture

## Goal

Pickleball Pro will be built as a multi-tenant SaaS application for clubs, leagues, coaches, and tournament organizers.

## Core Principles

- One codebase
- One GitHub repository
- One main production deployment
- Multiple clubs supported through tenant configuration
- Each club's data isolated by club_id
- Role-based access for admins, coaches, scorekeepers, and players
- Cloudflare-first hosting and deployment

## Environments

### Production
Branch: main

Used for stable customer-facing releases.

### Development
Branch: develop

Used for testing new work before release.

### Feature Branches
Pattern: feature/name-of-change

Used for isolated development.

## Main Concepts

### Tenant / Club
Each club is a tenant.

A club has:
- club_id
- name
- logo
- branding
- subscription plan
- active/inactive status

### Users
Users belong to one or more clubs.

Roles:
- owner
- admin
- coach
- scorekeeper
- player

### Tournament
A tournament belongs to one club.

### Players
Players belong to one club.

### Matches
Matches belong to one tournament and one club.

### Scores
Scores belong to matches.

## Data Isolation

Every major table should include club_id.

This prevents one club from seeing another club's data.

## Future Features

- Cloudflare Access login
- D1 database
- Per-club branding
- Subscription licensing
- SMS and email notifications
- Club-specific reports
- Audit logs
