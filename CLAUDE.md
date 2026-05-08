# Project guidance for Claude

This is a Flutter project. The rules below are non-negotiable and apply to every task.

## Pipeline (mandatory)

After ANY non-trivial change to `lib/`, you MUST:

1. Invoke the **Flutter Preflight** agent before reporting the task complete. It runs 7 specialist guards (lifecycle, state, async, platform, performance, security, build) in parallel and returns a consolidated report.
2. Address every BLOCKER finding and acknowledge every WARNING before continuing.
3. Before declaring a feature shippable, or before any release build, invoke the **Flutter QA Gate** agent. It runs the real toolchain (analyze, test, build) and is the only agent allowed to declare `READY TO SHIP`.

The `/ship` slash command runs both steps in sequence — prefer it.

## Process rules

- Never declare a task "done" without Preflight passing.
- Never claim "ready to ship" without QA Gate returning `READY TO SHIP`.
- If QA Gate fails, paste its verbatim output. Do not summarize failures.
- Codegen drift (`@freezed`, `@riverpod`, `@JsonSerializable`, `@RoutePage`) is always a BLOCKER — run `dart run build_runner build --delete-conflicting-outputs` and re-test.
- New permission-using packages (camera, location, mic, notifications, etc.) require a Platform Guard pass before merge — confirm Info.plist and AndroidManifest entries.

## Stack conventions
<!-- Fill these in for the specific project -->

- **State management:** <Riverpod | Bloc | Provider | other>
- **Routing:** <go_router | auto_route | other>
- **Networking:** <dio | http | retrofit>
- **Storage:** <flutter_secure_storage | hive | isar | sqlite>
- **Supported platforms:** <ios, android, web>
- **Min Flutter / Dart SDK:** <e.g. Flutter 3.24, Dart 3.5>

## What NOT to do

- Do not edit generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`).
- Do not commit secrets, service-account JSON, or `.env` files.
- Do not bypass the QA Gate by claiming "looks fine" — looks fine is not a verdict.
- Do not change `pubspec.yaml` without re-running `flutter pub get` and Build Guard.
- Do not silence analyzer errors with `// ignore:` without a comment justifying it.
