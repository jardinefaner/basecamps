// Persistent Command Center feed.
//
// Was: a `List<_FeedEntry>` in `_CommandScreenState`, lost the
// moment the user navigated away from /command.
//
// Now: a Riverpod `NotifierProvider` backed by SharedPreferences
// so the last N entries survive navigation, hot-restart, and
// app-resume. Newest-first ordering is enforced on insert.
//
// Stored as JSON in a single SharedPreferences key — the feed
// is bounded (50 entries max) so the round-trip cost is
// negligible. No Drift table needed; this is ephemeral UX state.

import 'dart:async';
import 'dart:convert';

import 'package:basecamp/features/experiment/command/command_tool.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One row in the feed. Mirrors the shape `_CommandScreenState`
/// kept inline but with explicit serialisation. `icon` is stored
/// as code-point + font-family pair (matching the
/// `CommandResult` design — IconData isn't const-constructable
/// from runtime data).
@immutable
class CommandFeedEntry {
  const CommandFeedEntry({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.iconCode,
    required this.iconFontFamily,
    required this.timestamp,
    required this.recordType,
    this.recordId,
    this.destinationPath,
    this.toolName,
    this.toolArgs,
    this.userInput,
  });

  final String title;
  final String subtitle;
  final String badge;
  final int iconCode;
  final String? iconFontFamily;
  final DateTime timestamp;
  final String recordType;
  final String? recordId;
  final String? destinationPath;
  final String? toolName;
  final Map<String, dynamic>? toolArgs;
  final String? userInput;

  IconData get icon =>
      IconData(iconCode, fontFamily: iconFontFamily ?? 'MaterialIcons');

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'subtitle': subtitle,
        'badge': badge,
        'iconCode': iconCode,
        'iconFontFamily': iconFontFamily,
        'timestamp': timestamp.toIso8601String(),
        'recordType': recordType,
        'recordId': recordId,
        'destinationPath': destinationPath,
        'toolName': toolName,
        'toolArgs': toolArgs,
        'userInput': userInput,
      };

  static CommandFeedEntry fromJson(Map<String, dynamic> j) {
    return CommandFeedEntry(
      title: j['title'] as String,
      subtitle: j['subtitle'] as String,
      badge: j['badge'] as String,
      iconCode: j['iconCode'] as int,
      iconFontFamily: j['iconFontFamily'] as String?,
      timestamp: DateTime.parse(j['timestamp'] as String),
      recordType: j['recordType'] as String,
      recordId: j['recordId'] as String?,
      destinationPath: j['destinationPath'] as String?,
      toolName: j['toolName'] as String?,
      toolArgs: (j['toolArgs'] as Map?)?.cast<String, dynamic>(),
      userInput: j['userInput'] as String?,
    );
  }
}

class CommandFeedNotifier extends Notifier<List<CommandFeedEntry>> {
  static const _prefsKey = 'command_feed_v1';
  static const _maxEntries = 50;

  @override
  List<CommandFeedEntry> build() {
    // Hydrate asynchronously — the build returns `[]` immediately
    // so first paint isn't blocked. The hydration overwrites
    // state once SharedPreferences resolves.
    unawaited(_hydrate());
    return const [];
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final entries = decoded
          .whereType<Map<String, dynamic>>()
          .map(CommandFeedEntry.fromJson)
          .toList();
      state = entries;
    } on Object catch (e, st) {
      debugPrint('[command-feed] hydrate failed: $e\n$st');
    }
  }

  /// Insert [entry] at the head; truncates to [_maxEntries].
  /// Persists asynchronously — fire-and-forget so the UI updates
  /// the moment state changes.
  void prepend(CommandFeedEntry entry) {
    final updated = <CommandFeedEntry>[entry, ...state];
    state = updated.length > _maxEntries
        ? updated.sublist(0, _maxEntries)
        : updated;
    unawaited(_persist());
  }

  /// Clear the entire feed. Used by the optional "Clear feed"
  /// affordance in the command bar's overflow menu.
  void clear() {
    state = const [];
    unawaited(_persist());
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode([for (final e in state) e.toJson()]);
      await prefs.setString(_prefsKey, raw);
    } on Object catch (e, st) {
      debugPrint('[command-feed] persist failed: $e\n$st');
    }
  }
}

final commandFeedProvider =
    NotifierProvider<CommandFeedNotifier, List<CommandFeedEntry>>(
  CommandFeedNotifier.new,
);

/// Convert a [CommandResult] to a feed entry. Stamps `timestamp`
/// to now and picks a `recordType` slug from the badge for the
/// recent-records routing window.
CommandFeedEntry feedEntryFromResult(
  CommandResult r, {
  required String recordType,
}) {
  return CommandFeedEntry(
    title: r.title,
    subtitle: r.subtitle,
    badge: r.badge,
    iconCode: r.iconCode,
    iconFontFamily: r.iconFontFamily,
    timestamp: DateTime.now(),
    recordType: recordType,
    recordId: r.recordId,
    destinationPath: r.destinationPath,
    toolName: r.toolName,
    toolArgs: r.toolArgs,
    userInput: r.userInput,
  );
}
