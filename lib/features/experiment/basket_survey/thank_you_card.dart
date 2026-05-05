// End-of-survey thank-you card for the basket-survey kiosk.
// Editorial paper-craft layout — parchment surface with grain,
// stamped print card framed by the signature offset-shadow border,
// italic-serif headline, name input + thank-you copy, and the
// kid's actual basket snapshot embedded in the centre.
//
// **The "basket and the overspill of emojis" in the centre is a
// snapshot of the live BasketWorld** captured the moment the
// survey completes — every marble in its settled position, every
// piece of overspill scattered around the basket, exactly as it
// looked just before the kid finished. The card freezes that
// moment.
//
// **Save flow** — the card now SAVES to the Prints tab instead
// of immediately printing. Tapping "Save to Prints" captures the
// inner card, writes it to `<docs>/prints/<id>.png`, inserts a
// `prints` row, and confirms with a toast. Adults batch-print
// later from the /prints screen. This decouples device-to-paper
// — kids can run surveys all day; printing happens when an adult
// is at a printer.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:basecamp/features/experiment/basket_survey/thank_you_card_helpers.dart';
import 'package:basecamp/features/prints/prints_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

/// Parchment + ink colors mirror the design reference.
const Color _parchment = Color(0xFFF2EDE4);
const Color _ink = Color(0xFF1A1A1A);
const Color _inkSoft = Color(0xFF555555);
const Color _inkLight = Color(0xFF999999);

/// "2024 – 2025" → "2024 – 2025" given today's date — picks the
/// academic year that contains today.
String _academicYear({DateTime? now}) {
  final n = now ?? DateTime.now();
  final start = n.month >= 8 ? n.year : n.year - 1;
  return '$start – ${start + 1}';
}

/// Full-screen thank-you overlay shown when the basket-survey
/// completes. The kid sees their basket frozen in time inside an
/// editorial print card; can type their name, tap Save to
/// Prints, or pass the device on to the next friend.
class BasketThankYouCard extends ConsumerStatefulWidget {
  const BasketThankYouCard({
    required this.basketSnapshot,
    required this.onPassAlong,
    super.key,
    this.surveyId,
    this.sessionId,
  });

  /// PNG of the BasketWorldWidget captured at end-of-survey. Null
  /// is tolerated — the card falls back to a placeholder so the
  /// kid still sees a card even if the capture failed.
  final Uint8List? basketSnapshot;

  /// FK references for the saved print. Both are optional —
  /// sandbox runs (no real Survey) save with both null and the
  /// print still appears in the /prints list.
  final String? surveyId;
  final String? sessionId;

  /// Called when the kid / teacher dismisses the card. The
  /// basket-survey screen wires this to its
  /// `_resetForNextChild` flow.
  final VoidCallback onPassAlong;

  @override
  ConsumerState<BasketThankYouCard> createState() =>
      _BasketThankYouCardState();
}

class _BasketThankYouCardState extends ConsumerState<BasketThankYouCard> {
  final TextEditingController _name = TextEditingController();
  final GlobalKey _printAreaKey = GlobalKey();
  bool _saving = false;
  bool _saved = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (_saving || _saved) return;
    setState(() => _saving = true);
    try {
      final png = await _captureCard();
      final repo = ref.read(printsRepositoryProvider);
      await repo.save(
        snapshot: png,
        kind: PrintKind.feelingsBasket,
        surveyId: widget.surveyId,
        sessionId: widget.sessionId,
        childName: _name.text.trim(),
        metadata: <String, dynamic>{
          'year': _academicYear(),
        },
      );
      if (!mounted) return;
      setState(() => _saved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved to Prints. Print it later from the Prints tab.'),
          duration: Duration(seconds: 4),
        ),
      );
    } on Object catch (e, st) {
      debugPrint('[basket-survey-save] failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save print: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Capture the print area at 3× pixel ratio so the embedded
  /// PNG stays crisp at A4. The print area excludes the action
  /// buttons (those live OUTSIDE the keyed RepaintBoundary).
  Future<Uint8List> _captureCard() async {
    final boundary = _printAreaKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final year = _academicYear();
    final serifTitle = GoogleFonts.dmSerifDisplay(
      fontStyle: FontStyle.italic,
      color: _ink,
    );
    final serifBody = GoogleFonts.dmSerifDisplay(
      color: _ink,
      fontStyle: FontStyle.italic,
    );
    final sansLabel = GoogleFonts.dmSans(
      fontWeight: FontWeight.w800,
      letterSpacing: 1.0,
      color: _inkLight,
    );

    return Material(
      color: _parchment,
      child: PaperGrain(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ——— Header outside the print card —————————
                    Text(
                      '"Your Feelings Jar"',
                      style: serifTitle.copyWith(
                        fontSize: 26,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'BASECAMP $year',
                      style: sansLabel.copyWith(fontSize: 11),
                    ),
                    const SizedBox(height: 20),

                    // ——— The print card itself ——————————————————
                    // Wrapped in RepaintBoundary so we can capture
                    // ONLY this for printing. Buttons sit outside
                    // — Flutter's @media print equivalent.
                    RepaintBoundary(
                      key: _printAreaKey,
                      child: StampPanel(
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(
                            20,
                            24,
                            20,
                            18,
                          ),
                          color: Colors.white,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'BASECamp Feelings Jar',
                                textAlign: TextAlign.center,
                                style: serifBody.copyWith(fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$year STUDENT SURVEY',
                                style: sansLabel.copyWith(
                                  fontSize: 9,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // The basket snapshot — drawn from
                              // the live world capture.
                              _BasketSnapshotFrame(
                                snapshot: widget.basketSnapshot,
                              ),
                              const SizedBox(height: 16),
                              _NameField(
                                controller: _name,
                                serif: serifBody,
                              ),
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: _ink.withValues(alpha: 0.12),
                                  ),
                                ),
                                child: Text(
                                  'Thank you for sharing your feelings '
                                  'with us. Every answer helps make '
                                  'BASECamp even better. You are '
                                  'awesome!',
                                  textAlign: TextAlign.center,
                                  style: serifBody.copyWith(
                                    fontSize: 14,
                                    color: _inkSoft,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),

                    // ——— Action buttons (outside the print area) —
                    // "Save to Prints" instead of inline print —
                    // the saved card lands in /prints for batch
                    // printing later from a single device. After
                    // save the button flips to a "Saved" state
                    // (disabled, check icon).
                    StampPanel(
                      onTap: _saving || _saved ? null : _onSave,
                      selected: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 36,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_saving)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    _parchment,
                                  ),
                                ),
                              )
                            else
                              Icon(
                                _saved
                                    ? Icons.check_circle_outline
                                    : Icons.bookmark_add_outlined,
                                color: _parchment,
                                size: 18,
                              ),
                            const SizedBox(width: 10),
                            Text(
                              _saving
                                  ? 'Saving…'
                                  : _saved
                                      ? 'Saved to Prints'
                                      : 'Save to Prints',
                              style: serifBody.copyWith(
                                fontSize: 15,
                                color: _parchment,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: widget.onPassAlong,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 26,
                          vertical: 10,
                        ),
                        child: Text(
                          'PASS TO NEXT FRIEND',
                          style: sansLabel.copyWith(
                            fontSize: 11,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frames the captured basket snapshot inside a neutral box and
/// lays a gift ribbon + tied bow on top of it — the basket-with-
/// emojis stays exactly as it was the moment the survey ended;
/// the ribbon "wraps" it for the keepsake. Falls back to a soft
/// placeholder if no snapshot was captured.
class _BasketSnapshotFrame extends StatelessWidget {
  const _BasketSnapshotFrame({required this.snapshot});

  final Uint8List? snapshot;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.4,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: const Color(0xFFFAF6EE),
            child: snapshot == null
                ? Center(
                    child: Text(
                      '(your jar)',
                      style: GoogleFonts.dmSerifDisplay(
                        fontStyle: FontStyle.italic,
                        color: _inkLight,
                        fontSize: 14,
                      ),
                    ),
                  )
                : Image.memory(
                    snapshot!,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
          ),
          // Ribbon overlay — drawn AFTER the snapshot so the bow
          // sits on top of the basket. The painter doesn't know
          // anything about the basket below it; the ribbon's
          // band lands across the upper third by default, which
          // ends up wrapping the basket's neck for our standard
          // snapshot composition.
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: BasketRibbonPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({required this.controller, required this.serif});
  final TextEditingController controller;
  final TextStyle serif;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'this jar belongs to:',
          style: serif.copyWith(fontSize: 12),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: TextField(
            controller: controller,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.words,
            maxLength: 24,
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: 'write your name',
              hintStyle: serif.copyWith(
                fontSize: 17,
                color: const Color(0xFFCCCCCC),
              ),
              border: const UnderlineInputBorder(
                borderSide: BorderSide(color: _ink, width: 2),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: _ink, width: 2),
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: _ink, width: 2),
              ),
            ),
            style: serif.copyWith(fontSize: 22),
          ),
        ),
      ],
    );
  }
}
