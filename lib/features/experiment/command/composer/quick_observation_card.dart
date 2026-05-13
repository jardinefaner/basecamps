// Quick observation composer — the structured-card flow spun up
// by the Spotlight-style picker in the Command Center.
//
// Design intent (from the May-13 redesign chat):
//   * Minimal upfront UI — note text + attachments. Everything
//     else (sentiment, domain, room, schedule) is edited later in
//     the dedicated observation tabs.
//   * Live child-tag suggestions: while the teacher types, every
//     name token (>= 2 chars) is matched against the active
//     program's roster. Matches show in a strip below the card;
//     tapping one ADDS a chip to the "Tagged" row (the word stays
//     in the prose).
//   * No silent auto-tag — even a single match still requires a
//     tap. Wrong-name tags are painful to clean up.
//   * Voice + typing both target this card while it's open; the
//     command bar above is greyed (the screen wires that — this
//     widget just owns its own text controller).
//
// Why a new card instead of reusing `ObservationComposer`:
// `ObservationComposer` is the full sheet (mood toggles, voice
// session, save-and-edit). The Command Center card is intentionally
// thinner so the teacher can dictate / save / move on in one
// motion. Refinements happen later in the observation detail
// screen.

import 'dart:async';

import 'package:basecamp/database/database.dart';
import 'package:basecamp/features/children/children_repository.dart'
    show childrenProvider;
import 'package:basecamp/features/observations/observations_repository.dart';
import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Result handed back to the parent on Save so it can push a feed
/// row referencing the new observation. The card itself only
/// knows the new id + a one-line preview.
class QuickObservationResult {
  const QuickObservationResult({required this.id, required this.preview});

  final String id;
  final String preview;
}

/// The card widget. The parent (`CommandScreen`) owns the
/// open/close state and routes voice transcripts in via [seedText].
/// The card returns a result via [onSaved], or null via [onCancel].
class QuickObservationCard extends ConsumerStatefulWidget {
  const QuickObservationCard({
    required this.onSaved,
    required this.onCancel,
    this.seedText = '',
    super.key,
  });

  /// Optional starter text — what the teacher had typed in the
  /// search bar at the moment they picked "Observation." The card
  /// drops the domain keyword from the front if present.
  final String seedText;

  final ValueChanged<QuickObservationResult> onSaved;
  final VoidCallback onCancel;

  @override
  ConsumerState<QuickObservationCard> createState() =>
      _QuickObservationCardState();
}

class _QuickObservationCardState
    extends ConsumerState<QuickObservationCard> {
  late final TextEditingController _note;
  final FocusNode _focus = FocusNode();
  final ImagePicker _picker = ImagePicker();

  final List<_PendingAttachment> _attachments = [];
  final Set<String> _taggedChildIds = <String>{};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: _strippedSeed(widget.seedText));
    // The textfield is the canonical input target while the card
    // is open; eagerly grabbing focus lets typed/voice characters
    // land here immediately without a manual tap on the field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant QuickObservationCard old) {
    super.didUpdateWidget(old);
    // The parent re-seeds when voice transcription is settled — we
    // append rather than replace so the teacher can mix typing +
    // dictation in the same draft.
    if (widget.seedText != old.seedText && widget.seedText.isNotEmpty) {
      final cleaned = _strippedSeed(widget.seedText);
      if (cleaned.isNotEmpty && !_note.text.endsWith(cleaned)) {
        final joiner = _note.text.isEmpty ||
                _note.text.endsWith(' ') ||
                _note.text.endsWith('\n')
            ? ''
            : ' ';
        _note.text = '${_note.text}$joiner$cleaned';
        _note.selection =
            TextSelection.collapsed(offset: _note.text.length);
      }
    }
  }

  @override
  void dispose() {
    _note.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Strip the leading "Observation: " / "obs " / "note," prefix
  /// the user typed when they selected the domain from the
  /// picker. Keeps the prose readable inside the card.
  String _strippedSeed(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final lower = t.toLowerCase();
    for (final prefix in const [
      'observation:',
      'observation,',
      'observation',
      'note:',
      'note,',
      'note',
      'obs:',
      'obs,',
      'obs',
    ]) {
      if (lower.startsWith(prefix)) {
        return t.substring(prefix.length).trimLeft();
      }
    }
    return t;
  }

  Future<void> _pickPhoto() async {
    try {
      final image = await _picker.pickImage(
        // Web's `image_picker` doesn't expose the camera at all —
        // calling `ImageSource.camera` throws a PlatformException.
        // Fall back to gallery so the button still works for web
        // users (who'd typically be uploading something already on
        // their drive anyway). Native gets the camera path.
        source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
        maxWidth: 2048,
      );
      if (image == null || !mounted) return;
      setState(() {
        _attachments.add(_PendingAttachment(kind: 'photo', file: image));
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Couldn’t add photo: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final video = await _picker.pickVideo(
        source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
        maxDuration: const Duration(seconds: 60),
      );
      if (video == null || !mounted) return;
      setState(() {
        _attachments.add(_PendingAttachment(kind: 'video', file: video));
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Couldn’t add video: $e');
    }
  }

  Future<void> _save() async {
    final note = _note.text.trim();
    if (note.isEmpty && _attachments.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(observationsRepositoryProvider);
      final id = await repo.addObservation(
        // The card commits with the catch-all values so the teacher
        // can refine later. The detail tabs render `other` +
        // `neutral` as "needs review" affordances.
        domains: const [ObservationDomain.other],
        sentiment: ObservationSentiment.neutral,
        note: note,
        childIds: _taggedChildIds.toList(),
        attachments: [
          for (final a in _attachments)
            ObservationAttachmentInput(
              kind: a.kind,
              localPath: a.file.path,
              source: a.file,
            ),
        ],
      );
      if (!mounted) return;
      // The parent calls `_closeComposer()` immediately after
      // `onSaved`, which removes this widget from the tree — so
      // resetting `_saving` here is belt-and-braces in case the
      // parent ever changes that contract (otherwise the button
      // would stay disabled on a zombie state).
      setState(() => _saving = false);
      widget.onSaved(QuickObservationResult(
        id: id,
        preview: note.isNotEmpty
            ? (note.length > 60 ? '${note.substring(0, 57)}…' : note)
            : '${_attachments.length} attachment'
                '${_attachments.length == 1 ? '' : 's'}',
      ));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Couldn’t save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final childrenAsync = ref.watch(childrenProvider);
    final suggestions = childrenAsync.maybeWhen(
      data: (children) => _matchChildren(
        text: _note.text,
        children: children,
        excluding: _taggedChildIds,
      ),
      orElse: () => const <Child>[],
    );
    final taggedChildren = childrenAsync.maybeWhen(
      data: (children) => [
        for (final c in children)
          if (_taggedChildIds.contains(c.id)) c,
      ],
      orElse: () => const <Child>[],
    );
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.4),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
              0,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.edit_note_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'New observation',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Cancel',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving ? null : widget.onCancel,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
            ),
            child: TextField(
              controller: _note,
              focusNode: _focus,
              maxLines: 4,
              minLines: 2,
              enabled: !_saving,
              // Rebuild on every keystroke so the suggestion strip
              // refreshes against the latest tokens.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'What happened?',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (taggedChildren.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                0,
              ),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: 4,
                children: [
                  for (final c in taggedChildren)
                    _TagChip(
                      label: _displayName(c),
                      onRemove: _saving
                          ? null
                          : () => setState(
                                () => _taggedChildIds.remove(c.id),
                              ),
                    ),
                ],
              ),
            ),
          if (_attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                0,
              ),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < _attachments.length; i++)
                    _AttachmentChip(
                      attachment: _attachments[i],
                      onRemove: _saving
                          ? null
                          : () => setState(() => _attachments.removeAt(i)),
                    ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                0,
              ),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Add photo',
                  onPressed: _saving ? null : _pickPhoto,
                  icon: const Icon(Icons.photo_camera_outlined),
                ),
                IconButton(
                  tooltip: 'Add video',
                  onPressed: _saving ? null : _pickVideo,
                  icon: const Icon(Icons.videocam_outlined),
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: _saving ||
                          (_note.text.trim().isEmpty &&
                              _attachments.isEmpty)
                      ? null
                      : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ),
          if (suggestions.isNotEmpty)
            _SuggestionStrip(
              suggestions: suggestions,
              onTap: _saving
                  ? null
                  : (c) =>
                      setState(() => _taggedChildIds.add(c.id)),
            ),
        ],
      ),
    );
  }
}

/// In-memory wrapper around an `XFile` picker handle. Held until
/// save so the repo can read bytes (web) or path (native) when
/// it copies into the observation-media directory.
class _PendingAttachment {
  _PendingAttachment({required this.kind, required this.file});

  final String kind;
  final XFile file;
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: Icon(
                Icons.close,
                size: 12,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment, required this.onRemove});

  final _PendingAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            attachment.kind == 'video'
                ? Icons.videocam_outlined
                : Icons.image_outlined,
            size: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            attachment.kind == 'video' ? 'Video' : 'Photo',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: Icon(
                Icons.close,
                size: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SuggestionStrip extends StatelessWidget {
  const _SuggestionStrip({required this.suggestions, required this.onTap});

  final List<Child> suggestions;
  final ValueChanged<Child>? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: 4,
        children: [
          for (final c in suggestions)
            ActionChip(
              avatar: const Icon(Icons.person_outline, size: 14),
              label: Text(_displayName(c)),
              onPressed: onTap == null ? null : () => onTap!(c),
              visualDensity: VisualDensity.compact,
              labelStyle: theme.textTheme.labelSmall,
            ),
        ],
      ),
    );
  }
}

String _displayName(Child c) {
  final last = c.lastName?.trim();
  if (last == null || last.isEmpty) return c.firstName;
  return '${c.firstName} ${last.substring(0, 1)}.';
}

/// Match every name token in [text] against [children], excluding
/// anyone already tagged. A token matches when it's a case-
/// insensitive prefix of the first or last name (>= 2 chars to
/// avoid the "i", "a" noise). Same child matched by multiple
/// tokens dedupes to one suggestion.
List<Child> _matchChildren({
  required String text,
  required List<Child> children,
  required Set<String> excluding,
}) {
  if (text.trim().isEmpty) return const <Child>[];
  final tokens = text
      .toLowerCase()
      .split(RegExp('[^a-z]+'))
      .where((t) => t.length >= 2)
      .toSet();
  if (tokens.isEmpty) return const <Child>[];
  final hits = <Child>[];
  final seen = <String>{};
  for (final c in children) {
    if (excluding.contains(c.id)) continue;
    final fn = c.firstName.toLowerCase();
    final ln = (c.lastName ?? '').toLowerCase();
    for (final t in tokens) {
      if (fn.startsWith(t) || (ln.isNotEmpty && ln.startsWith(t))) {
        if (seen.add(c.id)) hits.add(c);
        break;
      }
    }
    if (hits.length >= 6) break;
  }
  return hits;
}
