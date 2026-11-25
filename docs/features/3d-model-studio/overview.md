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
  Permissions: known
  Failure Scenarios: known
  Data Model: known
  Notifications: n/a
  Security: partial
  Analytics: n/a
  Dependencies: partial
  Acceptance Criteria: known
schema: 1
understanding_notes:
  Problem: Пользователю нужна одна рабочая область для просмотра, создания, правки моделей и подготовки геометрии к печати.
  Target Users: Подтверждены личное моделирование, изготовление деталей и художественная работа в пределах инструментов v1.
  Primary Workflow: Открыть или создать модель, доработать вручную или через AI, сохранить работу и экспортировать проверенную геометрию. В коде экспорт ещё отсутствует, а план I-9 по-прежнему описывает выбор формата как открытый.
  Permissions: Для правок по выделению отдельно подтверждаются доступ к дополнительной геометрии и применение изменений за пределами выделения.
  Failure Scenarios: Ошибка открытия сохраняет активную работу. Ошибка проверки геометрии блокирует экспорт и оставляет файл назначения в прежнем состоянии.
  Data Model: Сейчас импорт разворачивает сборку в сетку, а редактируемое сохранение хранит сетку, единицу и закреплённые размеры. По ответам Q-006 и Q-008 для 3MF требуется также сохранять связи со сборкой.
  Notifications: Отдельные уведомления для этих сценариев не требуются.
  Security: Правила доступа AI к геометрии заданы. Для Production ссылки ограничены частями открываемого пакета. Настройка провайдеров на чистом Mac ещё не проверена.
  Analytics: Аналитика для этих сценариев не требуется.
  Dependencies: PrusaSlicer выбран для приёмки. Текущая инструкция для провайдеров требует Docker Desktop, тогда как REQ-006 требует настройки без отдельной установки Docker. Это остаётся задачей реализации и проверки.
  Acceptance Criteria: Q-007 закреплён в REQ-009 как способ приёмки. Проверку размещения сборки нужно выполнить отдельно, если CLI показывает локальные размеры объектов. Фактическая приёмка ещё впереди. [Код PrusaSlicer 2.9.6](https://github.com/prusa3d/PrusaSlicer/blob/version_2.9.6/src/libslic3r/Model.cpp#L1160-L1177)
questions_left: 0
confirmed: 2026-11-25
updated: 2026-11-25
---

# 3D Model Studio

## Idea

Build a native macOS application with a Swift UI for viewing, creating, and editing 3D models through both direct geometry manipulation and a conversational AI agent. Users can configure the agent and model, describe changes, and apply AI instructions to selected geometry.

DEC-013 supersedes the Docker Desktop setup described in the earlier Dependencies note. Settings provisions native runtimes for Codex, Claude and Antigravity and saves the provider key in Keychain after a successful connection check. The [provider guide](../../../Providers/README.md) describes setup and recovery. Release acceptance still requires installation and Finder launch on one clean Mac without Docker Desktop, live authentication in Settings, and one applied modeling operation with each provider.

I-8 supersedes the historical Primary Workflow note about missing export and an open format choice in I-9. The File menu and toolbar export the current edited model as Core 3MF in millimeters under [REQ-009](requirements/REQ-009.md). The command validates the serialized mesh before writing. PrusaSlicer 2.9.7 reported 24 × 12 × 8 mm for the edited new block and 20 × 10 × 7 mm for the edited centimeter import. Separate package checks cover assembly placement. A PrusaSlicer GUI opening without a rescaling prompt or manual rescaling is pending for each file. [New block](../../../Fixtures/Export/created.3mf) · [Centimeter import](../../../Fixtures/Export/centimeter.3mf) · [CLI and placement evidence](../../../Fixtures/Export/README.md)

## Problem

Users need a single workspace to inspect 3D files, create geometry from descriptions, and refine it through a combination of manual edits and conversational instructions.

## Scope

Proposed v1, pending confirmation: a native macOS application with a Swift UI, basic 3D viewing, conversational model creation and revision, manual geometry editing, selection-based AI edits, exact dimensions and geometry checks for 3D printing, and agent/model settings. In v1, users can save and reopen both newly created and imported models for continued editing, with the edited geometry, its units, and any explicitly pinned dimensions restored on reopening. Users can also export the current geometry of either kind of model as Core 3MF while preserving its physical dimensions. Exported mesh coordinates are expressed in millimeters, and the file explicitly declares millimeters as its unit. PrusaSlicer is the reference slicer for acceptance testing. Use a basic visual appearance. Out of v1: advanced rendering and material authoring. Users must be able to open and view STL, OBJ, and 3MF models in v1. Both imported-model editing in all three formats and conversational model creation are required in v1, followed by manual and conversational refinement, with limited modeling capabilities in each. The intended modeling domain, the balance between creation and imported-model editing, and supported integration methods and modeling capabilities remain open. Codex, Claude, and Antigravity are required integrations in v1, with agent switching in settings. Users install 3D Model Studio, launch it from Finder, and connect all three agents through the app’s interface. The app prepares the required provider components, and setup requires no separate Docker installation. The underlying integration methods and supported modeling capabilities still require technical verification. Release acceptance on a clean Mac without Docker Desktop installed must demonstrate that a user can install the app, launch it from Finder, connect all three agents through the app, and complete a conversational modeling operation with each.
