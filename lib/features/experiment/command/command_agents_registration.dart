// Built-in command agents registration. Parallel to
// `command_tools_registration.dart` but for the agent-per-domain
// architecture. Each entry is one domain that owns its full CRUD
// surface via its primitives list.

import 'package:basecamp/features/experiment/command/agents/calendar_agent.dart';
import 'package:basecamp/features/experiment/command/agents/late_pickup_agent.dart';
import 'package:basecamp/features/experiment/command/agents/observations_agent.dart';
import 'package:basecamp/features/experiment/command/command_agent.dart';

void registerBuiltInAgents(CommandAgentRegistry registry) {
  registry.register(const CalendarAgent());
  registry.register(const ObservationsAgent());
  registry.register(const LatePickupAgent());
}

/// Side-effecting binder — main.dart imports this and calls it
/// during startup, before any consumer reads the registry
/// provider.
void wireCommandAgentRegistryAtStartup() {
  wireCommandAgentRegistry(registerBuiltInAgents);
}
