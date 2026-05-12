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

/// One row in the feed. Carries a state machine
/// (pending → done | failed) so cards can appear optimistically
/// the moment the user hits send + morph in place when the
/// dispatch completes. The input field is freed immediately —
/// the per-card progress lives on the card itself, not as a
/// global "loading" flag on the bar.
enum CommandFeedStatus {
  pending,
  done,
  failed,
}

@immutable
class CommandFeedEntry {
  const CommandFeedEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.iconCode,
    required this.iconFontFamily,
    required this.timestamp,
    required this.recordType,
    required this.status,
    this.recordId,
    this.destinationPath,
    this.toolName,
    this.toolArgs,
    this.userInput,
    this.errorMessage,
  });

  /// Stable id for this feed entry — distinct from
  /// [recordId] (which is the underlying domain object's id and
  /// only present after success). Used to update the entry in
  /// place when the dispatch resolves.
  final String id;

  final String title;
  final String subtitle;
  final String badge;
  final int iconCode;
  final String? iconFontFamily;
  final DateTime timestamp;
  final String recordType;
  final CommandFeedStatus status;
  final String? recordId;
  final String? destinationPath;
  final String? toolName;
  final Map<String, dynamic>? toolArgs;
  final String? userInput;

  /// Set when [status] == failed. Shown on the card with a
  /// Retry affordance.
  final String? errorMessage;

  IconData get icon =>
      IconData(iconCode, fontFamily: iconFontFamily ?? 'MaterialIcons');

  CommandFeedEntry copyWith({
    String? title,
    String? subtitle,
    String? badge,
    int? iconCode,
    String? iconFontFamily,
    String? recordType,
    CommandFeedStatus? status,
    String? recordId,
    String? destinationPath,
    String? toolName,
    Map<String, dynamic>? toolArgs,
    String? userInput,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return CommandFeedEntry(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      badge: badge ?? this.badge,
      iconCode: iconCode ?? this.iconCode,
      iconFontFamily: iconFontFamily ?? this.iconFontFamily,
      timestamp: timestamp,
      recordType: recordType ?? this.recordType,
      status: status ?? this.status,
      recordId: recordId ?? this.recordId,
      destinationPath: destinationPath ?? this.destinationPath,
      toolName: toolName ?? this.toolName,
      toolArgs: toolArgs ?? this.toolArgs,
      userInput: userInput ?? this.userInput,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'badge': badge,
        'iconCode': iconCode,
        'iconFontFamily': iconFontFamily,
        'timestamp': timestamp.toIso8601String(),
        'recordType': recordType,
        'status': status.name,
        'recordId': recordId,
        'destinationPath': destinationPath,
        'toolName': toolName,
        'toolArgs': toolArgs,
        'userInput': userInput,
        'errorMessage': errorMessage,
      };

  static CommandFeedEntry fromJson(Map<String, dynamic> j) {
    final statusStr = (j['status'] as String?) ?? 'done';
    final status = CommandFeedStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => CommandFeedStatus.done,
    );
    return CommandFeedEntry(
      id: (j['id'] as String?) ??
          // Pre-id entries that survived from older builds: synthesize
          // a stable-enough id from the timestamp so the new system
          // can address them.
          'legacy-${j['timestamp']}',
      title: j['title'] as String,
      subtitle: j['subtitle'] as String,
      badge: j['badge'] as String,
      iconCode: j['iconCode'] as int,
      iconFontFamily: j['iconFontFamily'] as String?,
      timestamp: DateTime.parse(j['timestamp'] as String),
      recordType: j['recordType'] as String,
      status: status,
      recordId: j['recordId'] as String?,
      destinationPath: j['destinationPath'] as String?,
      toolName: j['toolName'] as String?,
      toolArgs: (j['toolArgs'] as Map?)?.cast<String, dynamic>(),
      userInput: j['userInput'] as String?,
      errorMessage: j['errorMessage'] as String?,
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

  /// Replace the entry identified by [id] with [updated]. Used by
  /// the optimistic-flow: a pending entry is prepended immediately
  /// with the user's raw input, then this method swaps in the
  /// final card once the dispatch resolves. No-op when [id] isn't
  /// in the feed (the entry might've been trimmed past the cap or
  /// the user cleared the feed mid-flight).
  void replace(String id, CommandFeedEntry updated) {
    final idx = state.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    final next = [...state];
    next[idx] = updated;
    state = next;
    unawaited(_persist());
  }

  /// Convenience helper for the dispatcher: flip a pending entry
  /// to failed with [message]. Keeps the raw user input visible
  /// so the card serves as a retry surface.
  void markFailed(String id, String message) {
    final idx = state.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    final current = state[idx];
    final next = [...state];
    next[idx] = current.copyWith(
      status: CommandFeedStatus.failed,
      errorMessage: message,
    );
    state = next;
    unawaited(_persist());
  }

  /// Remove a feed entry — used by the "Dismiss" action on
  /// failed cards.
  void remove(String id) {
    final next = state.where((e) => e.id != id).toList();
    if (next.length == state.length) return;
    state = next;
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

/// Create an optimistic pending entry from the user's raw input.
/// The dispatcher's response (or failure) updates this entry in
/// place via `replace` / `markFailed`.
CommandFeedEntry pendingEntryFromInput(String input, {required String id}) {
  return CommandFeedEntry(
    id: id,
    title: input,
    subtitle: 'creating…',
    badge: 'WORKING',
    iconCode: Icons.hourglass_top_outlined.codePoint,
    iconFontFamily: Icons.hourglass_top_outlined.fontFamily,
    timestamp: DateTime.now(),
    recordType: 'pending',
    status: CommandFeedStatus.pending,
    userInput: input,
  );
}

/// Convert a [CommandResult] to a feed entry. Stamps `timestamp`
/// to now and picks a `recordType` slug from the badge for the
/// recent-records routing window.
CommandFeedEntry feedEntryFromResult(
  CommandResult r, {
  required String id,
  required String recordType,
}) {
  return CommandFeedEntry(
    id: id,
    title: r.title,
    subtitle: r.subtitle,
    badge: r.badge,
    iconCode: r.iconCode,
    iconFontFamily: r.iconFontFamily,
    timestamp: DateTime.now(),
    recordType: recordType,
    status: CommandFeedStatus.done,
    recordId: r.recordId,
    destinationPath: r.destinationPath,
    toolName: r.toolName,
    toolArgs: r.toolArgs,
    userInput: r.userInput,
  );
}
