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
import 'package:basecamp/features/experiment/command/tools/append_observation_tool.dart';
import 'package:basecamp/features/experiment/command/tools/late_pickup_tool.dart';
import 'package:basecamp/features/experiment/command/tools/observation_tool.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Side-effecting library — when imported, swaps the registry
/// loader callback to use the real registration list.
/// `main.dart` imports this and calls `wireCommandToolRegistry()`
/// at startup, before any consumer reads the provider.
void registerBuiltIns(CommandToolRegistry registry, Ref ref) {
  // Order doesn't affect routing — the registry just lists them
  // for the LLM. Keep them grouped by domain for readability.
  registry.register(const CreateObservationTool());
  registry.register(const AppendObservationTool());
  registry.register(const CreateLatePickupTool());
  // Calendar moved to the new agent-per-domain architecture —
  // see `command_agents_registration.dart`. CreateCalendarTileTool
  // and EditCalendarTileTool now live inside `CalendarAgent`'s
  // primitives list, not in the flat tool registry.
}

/// Call this once at app start (e.g. main.dart, after Riverpod
/// is up) so `commandToolRegistryProvider` sees a real loader.
void wireCommandToolRegistry() {
  registerBuiltInCommandTools = registerBuiltIns;
}
