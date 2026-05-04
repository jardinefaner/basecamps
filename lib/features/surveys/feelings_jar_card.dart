// End-of-survey thank-you card for the BASECamp Student Survey.
//
// Shows a printable card containing:
//   * Header: "BASECamp Feelings Jar 2025–2026" (academic year
//     auto-derived from today's date so it ages with the program).
//   * The kid's actual jar — the live Flame canvas (jar + every
//     marble they dropped, in their final resting position) is
//     snapshotted via RepaintBoundary the moment they finish, and
//     embedded here as a PNG. A wooden cap + ribbon are painted
//     ON TOP so the snapshot reads as "sealed for keeps".
//   * "This jar belongs to:" — TextField for the child's name.
//   * Thank-you message.
//   * "Print My Jar" — generates a PDF that mirrors the on-screen
//     card (header + sealed jar + name + thanks). Routes through
//     the existing `printing` package so iOS/Android/web all use
//     the same code path: native print sheet on mobile, browser
//     print dialog on web.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:basecamp/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// "Calendar 2025-2026" → "2025–2026". Determined by today's date:
/// if we're in Aug-Dec, year-pair is `<thisYear>-<thisYear+1>`,
/// else `<thisYear-1>-<thisYear>`.
String currentAcademicYear({DateTime? now}) {
  final n = now ?? DateTime.now();
  final start = n.month >= 8 ? n.year : n.year - 1;
  return '$start–${start + 1}';
}

/// The end-of-survey thank-you card. The [jarSnapshot] is the
/// rasterized live Flame canvas captured from the kiosk the moment
/// the kid answered the last question — it includes their actual
/// marbles in their settled positions.
class FeelingsJarCard extends StatefulWidget {
  const FeelingsJarCard({
    required this.jarSnapshot,
    required this.siteName,
    required this.classroom,
    required this.onDone,
    super.key,
    this.academicYear,
  });

  /// PNG bytes of the live game canvas at end-of-survey. May be
  /// null if capture failed (e.g. the canvas wasn't ready); the
  /// card falls back to a placeholder rather than blocking the
  /// flow.
  final Uint8List? jarSnapshot;

  final String siteName;
  final String classroom;

  /// Pre-computed for testability; defaults to `currentAcademicYear()`.
  final String? academicYear;

  /// Called when the child / teacher dismisses the card to
  /// continue to the next child. The kiosk wires this to its
  /// reset routine.
  final VoidCallback onDone;

  @override
  State<FeelingsJarCard> createState() => _FeelingsJarCardState();
}

class _FeelingsJarCardState extends State<FeelingsJarCard> {
  final TextEditingController _nameCtrl = TextEditingController();
  final GlobalKey _cardKey = GlobalKey();
  bool _printing = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _onPrint() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      final pngBytes = await _captureCardAsPng();
      final nameSlug = _nameCtrl.text.trim().isEmpty
          ? 'jar'
          : _nameCtrl.text.trim();
      await Printing.layoutPdf(
        name: 'BASECamp Feelings Jar — '
            '${widget.classroom} — $nameSlug',
        onLayout: (format) async => _buildPdfPage(format, pngBytes),
      );
    } on Object catch (e, st) {
      debugPrint('[feelings-jar] print failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not print: $e')),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  /// Snapshot the card widget tree (header + jar + name + thanks)
  /// at 3× pixel ratio so the PDF embed stays crisp at A4.
  Future<Uint8List> _captureCardAsPng() async {
    final boundary = _cardKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// PDF page builder. Renders the captured PNG centered on the
  /// page; the print dialog handles paper size + margins.
  Future<Uint8List> _buildPdfPage(
    PdfPageFormat format,
    Uint8List pngBytes,
  ) async {
    final doc = pw.Document();
    final image = pw.MemoryImage(pngBytes);
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => pw.Center(
          child: pw.Image(image),
        ),
      ),
    );
    return doc.save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final year = widget.academicYear ?? currentAcademicYear();
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.lg,
          ),
          child: Column(
            children: [
              // Repaint boundary wraps everything that should appear
              // in the PDF — chrome (buttons, scaffold) sits OUTSIDE
              // it. This is the @media-print equivalent: only the
              // wrapped subtree gets snapshotted for print output.
              RepaintBoundary(
                key: _cardKey,
                child: ColoredBox(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'BASECamp Feelings Jar  $year',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: const Color(0xFF1A2C2A),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${widget.siteName} · ${widget.classroom}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF50625F),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        AspectRatio(
                          aspectRatio: 0.78, // narrow + tall jar
                          child: _SealedJarSnapshot(
                            snapshot: widget.jarSnapshot,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _NameField(controller: _nameCtrl),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Thank you for sharing your feelings\n'
                          'with us this year. 💚',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF50625F),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              // Action chrome — outside the RepaintBoundary so the
              // print output doesn't include buttons.
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _printing ? null : _onPrint,
                    icon: _printing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print_outlined),
                    label: Text(_printing ? 'Preparing…' : 'Print My Jar'),
                  ),
                  TextButton(
                    onPressed: widget.onDone,
                    child: const Text('Pass to next friend'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm, bottom: 8),
            child: Text(
              'This jar belongs to:',
              style: theme.textTheme.titleMedium?.copyWith(
                color: const Color(0xFF50625F),
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.words,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A2C2A),
              ),
              decoration: const InputDecoration(
                hintText: '___________',
                isDense: true,
                border: UnderlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The jar slot in the printable card. Renders the live snapshot
/// (or a soft fallback if capture failed) with a wooden cap +
/// ribbon painted on top to "seal" it for printing.
class _SealedJarSnapshot extends StatelessWidget {
  const _SealedJarSnapshot({required this.snapshot});

  final Uint8List? snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            // The captured jar — fills the slot, contains the
            // child's actual marbles in their settled positions.
            Positioned.fill(
              child: snapshot == null
                  ? const _JarSnapshotFallback()
                  : Image.memory(
                      snapshot!,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
            ),
            // Cap + ribbon overlay — sized relative to the slot so
            // the bow lands at the rim of the snapshot's jar.
            Positioned(
              top: 0,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight * 0.20,
                child: CustomPaint(
                  painter: _CapAndRibbonPainter(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _JarSnapshotFallback extends StatelessWidget {
  const _JarSnapshotFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF7FBF8),
      child: Center(
        child: Text(
          '(jar)',
          style: TextStyle(color: Color(0xFF7D8B88)),
        ),
      ),
    );
  }
}

/// Wooden cap + ribbon painted ON TOP of the captured jar
/// snapshot. Drawn proportional to its slot so it scales with the
/// card. The geometry matches the rim of the live jar (which sits
/// in the upper portion of the canvas).
class _CapAndRibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // The kiosk jar's neck is roughly 55% of canvas width, centered.
    final neckW = w * 0.50;
    final centerX = w / 2;
    final capH = h * 0.55;
    final capY = h * 0.10;

    // Wooden cap.
    final capRect = Rect.fromLTWH(
      centerX - neckW / 2 - 8,
      capY,
      neckW + 16,
      capH,
    );
    final capRRect = RRect.fromRectAndRadius(capRect, const Radius.circular(8));
    final capPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFB47A48), Color(0xFF8A562B)],
      ).createShader(capRect);
    canvas.drawRRect(capRRect, capPaint);
    // Wood-grain streaks.
    final grain = Paint()
      ..color = const Color(0x33000000)
      ..strokeWidth = 0.8;
    for (var i = 0; i < 5; i++) {
      final y = capRect.top + capH * (0.18 + i * 0.16);
      canvas.drawLine(
        Offset(capRect.left + 6, y),
        Offset(capRect.right - 6, y),
        grain,
      );
    }
    canvas.drawRRect(
      capRRect,
      Paint()
        ..color = const Color(0xFF6B3F1B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Ribbon band — wraps the rim just below the cap.
    final bandH = h * 0.18;
    final bandY = capRect.bottom - bandH * 0.45;
    final ribbonRect = Rect.fromLTWH(
      centerX - neckW / 2 - 14,
      bandY,
      neckW + 28,
      bandH,
    );
    canvas.drawRect(
      ribbonRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5DCAA5), Color(0xFF3A9C7B)],
        ).createShader(ribbonRect),
    );
    // Stitch line.
    final stitch = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(ribbonRect.left, ribbonRect.center.dy),
      Offset(ribbonRect.right, ribbonRect.center.dy),
      stitch,
    );

    // Bow on the left of the ribbon.
    _paintBow(
      canvas,
      Offset(ribbonRect.left + ribbonRect.width * 0.30, ribbonRect.center.dy),
      bandH,
    );
  }

  void _paintBow(Canvas canvas, Offset c, double bandH) {
    final loopR = bandH * 0.85;
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF5DCAA5), Color(0xFF3A9C7B)],
      ).createShader(Rect.fromCircle(center: c, radius: loopR * 1.4))
      ..style = PaintingStyle.fill;
    final left = Path()
      ..moveTo(c.dx, c.dy)
      ..quadraticBezierTo(
        c.dx - loopR * 1.4, c.dy - loopR * 0.85,
        c.dx - loopR * 1.3, c.dy,
      )
      ..quadraticBezierTo(
        c.dx - loopR * 1.4, c.dy + loopR * 0.85,
        c.dx, c.dy,
      )
      ..close();
    canvas.drawPath(left, paint);
    final right = Path()
      ..moveTo(c.dx, c.dy)
      ..quadraticBezierTo(
        c.dx + loopR * 1.4, c.dy - loopR * 0.85,
        c.dx + loopR * 1.3, c.dy,
      )
      ..quadraticBezierTo(
        c.dx + loopR * 1.4, c.dy + loopR * 0.85,
        c.dx, c.dy,
      )
      ..close();
    canvas
      ..drawPath(right, paint)
      ..drawCircle(c, loopR * 0.40, paint);
    final tail1 = Path()
      ..moveTo(c.dx - loopR * 0.3, c.dy + loopR * 0.2)
      ..lineTo(c.dx - loopR * 0.55, c.dy + loopR * 1.6)
      ..lineTo(c.dx - loopR * 0.1, c.dy + loopR * 1.4)
      ..close();
    canvas.drawPath(tail1, paint);
    final tail2 = Path()
      ..moveTo(c.dx + loopR * 0.3, c.dy + loopR * 0.2)
      ..lineTo(c.dx + loopR * 0.55, c.dy + loopR * 1.6)
      ..lineTo(c.dx + loopR * 0.1, c.dy + loopR * 1.4)
      ..close();
    canvas.drawPath(tail2, paint);
  }

  @override
  bool shouldRepaint(covariant _CapAndRibbonPainter oldDelegate) => false;
}
