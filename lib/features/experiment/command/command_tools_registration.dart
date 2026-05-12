// Built-in command tools registration.
//
// Every feature module that exposes a CommandTool registers it
// here. Keep this file tiny — it's just the wiring; tool
// implementations live alongside their feature.
//
// Adding a new tool: import its class, register it in the
// `registerBuiltInCommandTools` body. The bar picks it up
// automatically (no central classifier prompt to maintain).

import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Side-effecting library — when imported, swaps the registry
/// loader callback to use the real registration list.
/// `main.dart` imports this and calls `wireCommandToolRegistry()`
/// at startup, before any consumer reads the provider.
void registerBuiltIns(CommandToolRegistry registry, Ref ref) {
  // Every domain has migrated to the agent-per-domain
  // architecture (see `command_agents_registration.dart`). The
  // flat tool registry is intentionally empty — it stays only
  // so the dispatcher's "tool fallback" path keeps compiling
  // and so future ad-hoc tools that don't belong to a domain
  // (one-off utility actions, time-bounded experiments) have a
  // home without touching agent code.
}

/// Call this once at app start (e.g. main.dart, after Riverpod
/// is up) so `commandToolRegistryProvider` sees a real loader.
void wireCommandToolRegistry() {
  registerBuiltInCommandTools = registerBuiltIns;
}
