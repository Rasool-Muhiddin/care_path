import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Small-phone layout audit: renders a screen at [phoneWidth] dp with a
/// larger system font ([textScale]) and real font metrics, then reports
/// every text that was cut off ("…", fade, clip) and every overflow.
///
/// Fonts: the default test font draws every glyph as a 1 em square (about
/// twice as wide as real text), so it would flag almost everything. We load
/// a real font under the family name "Roboto" (what Material uses on
/// Android): Arial when available (covers Latin + Arabic, read from the
/// system at test time, never committed), otherwise Roboto from the
/// Flutter SDK (Latin only — Arabic screens are then skipped).
const double phoneWidth = 360;
const double textScale = 1.3;

bool _fontsLoaded = false;
bool arabicFontAvailable = false;

Future<void> loadAuditFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final candidates = <(String, bool)>[
    ('C:/Windows/Fonts/arial.ttf', true),
    ('/usr/share/fonts/truetype/msttcorefonts/Arial.ttf', true),
    ('${Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter'}/bin/cache/artifacts/material_fonts/roboto-regular.ttf', false),
  ];
  for (final (path, hasArabic) in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    arabicFontAvailable = hasArabic;
    return;
  }
}

/// A text that was visually cut, or a layout overflow.
class LayoutProblem {
  LayoutProblem(this.kind, this.text);
  final String kind;
  final String text;
  @override
  String toString() => '$kind: "$text"';
}

/// Texts the app truncates on purpose (one-line previews of free text).
const _intentional = <String>{};

List<LayoutProblem> findTruncatedText(WidgetTester tester, {Set<String> allow = const {}}) {
  final problems = <LayoutProblem>[];
  for (final r in tester.allRenderObjects) {
    if (r is! RenderParagraph || !r.hasSize || r.size.isEmpty) continue;
    final text = r.text.toPlainText().trim();
    if (text.isEmpty || allow.contains(text) || _intentional.contains(text)) continue;
    final oneLine = r.maxLines == 1 || !r.softWrap;
    final tooWide = oneLine && r.getMaxIntrinsicWidth(double.infinity) > r.size.width + 0.5;
    if (r.didExceedMaxLines || tooWide) problems.add(LayoutProblem('truncated', text));
  }
  return problems;
}

/// Pumps [child] inside the app's MaterialApp setup (Arabic locale, as in
/// main.dart) at phone size and returns the problems found, after running
/// [interact] (e.g. switching tabs) if given.
Future<List<LayoutProblem>> auditScreen(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Future<void> Function(WidgetTester tester)? interact,
  Set<String> allow = const {},
  double height = 4000,
}) async {
  await loadAuditFonts();
  tester.view.physicalSize = Size(phoneWidth, height);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final overflows = <LayoutProblem>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains('overflowed')) {
      // Where: the creation location of the overflowing widget in lib/.
      final where = RegExp(r'lib/[^\s:]+\.dart:\d+').firstMatch(details.toString())?.group(0) ?? '?';
      overflows.add(LayoutProblem('overflow', '${message.split('\n').first} at $where'));
    } else {
      previous?.call(details);
    }
  };
  try {
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: child,
      ),
    ));
    await tester.pumpAndSettle();
    if (interact != null) {
      await interact(tester);
      await tester.pumpAndSettle();
    }
    return [...overflows, ...findTruncatedText(tester, allow: allow)];
  } finally {
    FlutterError.onError = previous;
  }
}
