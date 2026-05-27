# Changelog

## v6.3.0 - 2026-05-27

### Changed

- Removed the self-installing OpenClaw LLM cron keepalive flow from `SKILL.md`.
- Replaced passive keepalive with `scripts/status_board_keepalive.sh`, a curl-based script that does not trigger agentTurn or load skills.
- Changed status-board activation guidance to only read `.openclaw/heartbeat.json` and remind admins when external keepalive is missing.
- Marked `keepalive-cron-job.json` as deprecated so it is not copied into OpenClaw cron config again.

### Added

- Added `docs/zero-token-keepalive.md` with installation and verification steps for the external keepalive script.
- Added `docs/migrate-from-llm-cron.md` with instructions for disabling old `status-board-keepalive` LLM cron jobs.

### Migration

- Remove or disable old `status-board-keepalive` jobs from `/workspace/projects/cron/jobs.json` and `/workspace/projects/workspace/cron/jobs.json`.
- Install `scripts/status_board_keepalive.sh` with a system cron or platform scheduler, recommended at 30-minute intervals.
