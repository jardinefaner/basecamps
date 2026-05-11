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
import 'package:basecamp/features/experiment/command/tools/observation_tool.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Side-effecting library — when imported, swaps the registry
/// loader callback to use the real registration list.
/// `command_screen.dart` (and any future Command Center entry
/// point) imports this file at the top of its imports to wire
/// up the registry.
void registerBuiltIns(CommandToolRegistry registry, Ref ref) {
  // Phase 0: the four existing intents converted to tools.
  // Today only `create_observation` lives here as the proof —
  // append / calendar / late-pickup will follow as they're
  // ported. Until then the bar's old 2-pass classifier still
  // handles them; this registry just stands ready.
  registry.register(const CreateObservationTool());
}

/// Call this once at app start (e.g. main.dart, after Riverpod
/// is up) so `commandToolRegistryProvider` sees a real loader.
void wireCommandToolRegistry() {
  registerBuiltInCommandTools = registerBuiltIns;
}
