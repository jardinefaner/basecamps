import 'package:flutter/material.dart';

/// Sandbox surface for trying things out before they earn a real home.
///
/// The launcher's Experiment tile lands here. It's intentionally
/// barren — a blank canvas plus a single FAB — so each new
/// "what if we tried X" idea has a no-pressure place to render
/// without us scaffolding a route, an entry, and a category for
/// every throwaway. When an experiment graduates, lift it into its
/// own feature directory + route; until then it lives in here.
///
/// Today: just the FAB. Tomorrow: whatever the next experiment is.
class ExperimentScreen extends StatelessWidget {
  const ExperimentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Experiment'),
      ),
      // Empty body on purpose — this is the blank canvas the FAB
      // sits on top of. Whatever experiment is current will paint
      // its own contents in here later.
      body: const SizedBox.expand(),
      floatingActionButton: FloatingActionButton(
        // No-op for now. The point of the first experiment is just
        // the FAB existing on a blank canvas — the action it triggers
        // is the next experiment's job to define.
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}
