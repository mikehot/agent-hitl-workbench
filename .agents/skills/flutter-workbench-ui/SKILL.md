---
name: flutter-workbench-ui
description: Use when creating or refactoring Flutter pages, BaseViewModel / UiState flows, responsive 3-pane Web/macOS workbench layouts, Android adaptive views, or replay/live repository wiring in app/. Do not use for Python-only backend logic.
---

# Flutter Cross-Platform Workbench UI Workflow

## Before You Start

- Read `AGENTS.md` and inspect `app/lib/core/` (`BasePage`, `BaseViewModel`, `UiState`, `BaseRepository`).
- Keep Web (Cloudflare Pages static demo), macOS desktop, and Android compatibility intact (guard `dart:io` behind conditional imports or avoid `dart:io` in shared UI/network code).

## Workflow

1. Model screen state cleanly with `UiState<T>` and `BaseViewModel<T>`.
2. Support wide (`>= 960px`) 3-pane workbench layout (Document Preview | Live Node Trace | Editable Approval Form) and narrow (`< 960px`) segmented/tab layout for Android devices.
3. Ensure embedded sandbox replay works even when no backend server is reachable (Cloudflare Pages zero-cost demo mode), while switching cleanly to live `FastAPI` endpoints when configured.
4. Run static analysis and widget tests.

## Validation

- `cd app && dart analyze lib/ && flutter test`

## Do Not

- Do not import `dart:io` directly in Web-compiled files.
- Do not upgrade `flutter_riverpod` across major versions without explicit user approval.
