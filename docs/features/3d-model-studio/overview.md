---
type: feature
id: 3d-model-studio
title: 3D Model Studio
status: implementing
owner: Boris Tsekinovsky
created: 2026-11-25
provenance: Created from the new-project intake
understanding:
  Problem: known
  Target Users: known
  Primary Workflow: known
  Permissions: partial
  Failure Scenarios: partial
  Data Model: partial
  Notifications: n/a
  Security: unknown
  Analytics: n/a
  Dependencies: partial
  Acceptance Criteria: partial
schema: 1
understanding_notes:
  Problem: Нужно единое приложение для просмотра, создания и ручной и разговорной доработки 3D-моделей.
  Target Users: В Q-001 приняты все три предложенные группы пользователей; точные размеры и проверка геометрии для 3D-печати подтверждены отдельно.
  Primary Workflow: Подтверждены открытие существующей модели или создание через AI, затем ручные и разговорные правки, включая выбранные грани.
  Permissions: Работа агента с моделью предусмотрена; границы доступа к другим файлам пока не определены.
  Failure Scenarios: Нужны обработка ошибок импорта, недоступности агента и неудачных изменений; конкретное поведение ещё не описано.
  Data Model: Нужны геометрия, выбор граней и точные размеры; внутреннее представление определит реализация.
  Notifications: Отдельные уведомления не запрошены.
  Security: Способ авторизации агентов и границы передачи данных ещё не установлены.
  Analytics: Аналитика не запрошена.
  Dependencies: Все три агента обязательны в v1. Доступные способы интеграции и возможности каждого требуют технической проверки.
  Acceptance Criteria: Основной объём v1 и выбор агентов определены; покрытие импорта, допуски размеров и критерии проверки геометрии предстоит конкретизировать при технической проработке.
questions_left: 0
confirmed: 2026-11-25
---

# 3D Model Studio

## Idea

Build a native macOS application with a Swift UI for viewing, creating, and editing 3D models through both direct geometry manipulation and a conversational AI agent. Users can configure the agent and model, describe changes, and apply AI instructions to selected geometry.

## Problem

Users need a single workspace to inspect 3D files, create geometry from descriptions, and refine it through a combination of manual edits and conversational instructions.

## Scope

Proposed v1, pending confirmation: a native macOS application with a Swift UI, basic 3D viewing, conversational model creation and revision, manual geometry editing, selection-based AI edits, exact dimensions and geometry checks for 3D printing, and agent/model settings. In v1, users can save and reopen both newly created and imported models for continued editing, with the edited geometry, its units, and any explicitly pinned dimensions restored on reopening. Users can also export the current geometry of either kind of model in one slicer-compatible format while preserving its physical dimensions. The export format remains open. Use a basic visual appearance. Out of v1: advanced rendering and material authoring. Users must be able to open and view STL, OBJ, and 3MF models in v1. Both imported-model editing in all three formats and conversational model creation are required in v1, followed by manual and conversational refinement, with limited modeling capabilities in each. The intended modeling domain, the balance between creation and imported-model editing, and supported integration methods and modeling capabilities remain open. Codex, Claude, and Antigravity are required integrations in v1, with agent switching in settings; their supported integration methods and modeling capabilities still require technical verification.
