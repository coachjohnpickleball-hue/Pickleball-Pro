# Scheduler Refactor

## Purpose

The scheduler currently lives mostly inside `worker/src/app.html`.

The goal is to gradually extract scheduler logic into testable service modules without breaking the working app.

## Step 1: Safety Rules

The first extracted module is:

services/scheduler/safety.mjs

It defines how the app decides which rounds are protected from regeneration.

## Protected Rounds

A round is protected if:

- any match in the round has a completed score, or
- the round has been marked as started.

Protected rounds must not be changed by schedule regeneration.

## Refactor Rule

Do not move the whole scheduler at once.

Move one safe piece at a time, add tests, then wire it into the app.
