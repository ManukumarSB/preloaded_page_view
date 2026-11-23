import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preloaded_page_view/preloaded_page_view.dart';

const _size = Size(400, 800);

/// Records which pages are alive, and which ever got disposed.
class _Tracker {
  final alive = <int>{};
  final disposed = <int>[];
  final builds = <int, int>{};
}

class _Page extends StatefulWidget {
  const _Page(this.index, this.tracker);
  final int index;
  final _Tracker tracker;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    widget.tracker.alive.add(widget.index);
  }

  @override
  void dispose() {
    widget.tracker.alive.remove(widget.index);
    widget.tracker.disposed.add(widget.index);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.tracker.builds.update(widget.index, (n) => n + 1, ifAbsent: () => 1);
    final current = PreloadedPageView.isCurrentPage(context);
    return Text('${widget.index}:${current ? 'current' : 'preloaded'}');
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  TextDirection textDirection = TextDirection.ltr,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(textDirection: textDirection, child: child),
  );
}

Widget _builder(
  _Tracker tracker, {
  int preload = 1,
  int itemCount = 20,
  PageController? controller,
  Axis scrollDirection = Axis.horizontal,
  bool reverse = false,
  ValueChanged<int>? onPageChanged,
}) {
  return PreloadedPageView.builder(
    preloadPagesCount: preload,
    controller: controller,
    scrollDirection: scrollDirection,
    reverse: reverse,
    onPageChanged: onPageChanged,
    itemCount: itemCount,
    itemBuilder: (context, index) => _Page(index, tracker),
  );
}

Future<void> _swipeNext(
  WidgetTester tester, {
  Offset delta = const Offset(-300, 0),
}) async {
  await tester.fling(find.byType(PreloadedPageView), delta, 1000);
  await tester.pumpAndSettle();
}

void main() {
  group('preloading', () {
    for (final n in [0, 1, 2, 3]) {
      testWidgets('builds the current page and $n on each side', (
        tester,
      ) async {
        final tracker = _Tracker();
        await _pump(
          tester,
          _builder(
            tracker,
            preload: n,
            controller: PageController(initialPage: 5),
          ),
        );

        expect(tracker.alive, {for (var i = 5 - n; i <= 5 + n; i++) i});
      });
    }

    testWidgets('does not build before page 0', (tester) async {
      final tracker = _Tracker();
      await _pump(tester, _builder(tracker, preload: 2));

      expect(tracker.alive, {0, 1, 2});
    });

    testWidgets('does not build past the last page', (tester) async {
      final tracker = _Tracker();
      await _pump(
        tester,
        _builder(
          tracker,
          preload: 3,
          itemCount: 4,
          controller: PageController(initialPage: 3),
        ),
      );

      expect(tracker.alive, {0, 1, 2, 3});
    });

    testWidgets('moves the window along as you swipe', (tester) async {
      final tracker = _Tracker();
      await _pump(tester, _builder(tracker, preload: 2));

      await _swipeNext(tester);
      expect(tracker.alive, {0, 1, 2, 3});

      await _swipeNext(tester);
      await _swipeNext(tester);
      expect(tracker.alive, {1, 2, 3, 4, 5});
      expect(tracker.disposed, [0]);
    });

    testWidgets('jumpToPage preloads around the new page', (tester) async {
      final tracker = _Tracker();
      final controller = PageController();
      addTearDown(controller.dispose);
      await _pump(tester, _builder(tracker, controller: controller));

      controller.jumpToPage(10);
      await tester.pump();

      expect(tracker.alive, {9, 10, 11});
    });

    testWidgets('counts pages, not viewports, with viewportFraction', (
      tester,
    ) async {
      final tracker = _Tracker();
      final controller = PageController(viewportFraction: 0.5, initialPage: 6);
      addTearDown(controller.dispose);
      await _pump(
        tester,
        _builder(tracker, preload: 2, controller: controller),
      );

      // Page 6 is centered with half of 5 and 7 visible; 2 more each side.
      expect(tracker.alive, {3, 4, 5, 6, 7, 8, 9});
    });

    testWidgets('changing preloadPagesCount takes effect', (tester) async {
      final tracker = _Tracker();
      final controller = PageController(initialPage: 5);
      addTearDown(controller.dispose);
      await _pump(tester, _builder(tracker, controller: controller));
      expect(tracker.alive, {4, 5, 6});

      await _pump(
        tester,
        _builder(tracker, preload: 3, controller: controller),
      );
      expect(tracker.alive, {2, 3, 4, 5, 6, 7, 8});

      await _pump(
        tester,
        _builder(tracker, preload: 0, controller: controller),
      );
      expect(tracker.alive, {5});
    });
  });

  group('directions', () {
    testWidgets('vertical', (tester) async {
      final tracker = _Tracker();
      await _pump(tester, _builder(tracker, scrollDirection: Axis.vertical));

      await _swipeNext(tester, delta: const Offset(0, -500));

      expect(find.text('1:current'), findsOneWidget);
      expect(tracker.alive, {0, 1, 2});
    });

    testWidgets('right-to-left swipes the other way', (tester) async {
      final tracker = _Tracker();
      await _pump(tester, _builder(tracker), textDirection: TextDirection.rtl);

      await _swipeNext(tester, delta: const Offset(300, 0));

      expect(find.text('1:current'), findsOneWidget);
    });

    testWidgets('reverse', (tester) async {
      final tracker = _Tracker();
      await _pump(tester, _builder(tracker, reverse: true));

      await _swipeNext(tester, delta: const Offset(300, 0));

      expect(find.text('1:current'), findsOneWidget);
    });
  });

  group('current page', () {
    testWidgets('onPageChanged fires once per page', (tester) async {
      final pages = <int>[];
      await _pump(tester, _builder(_Tracker(), onPageChanged: pages.add));

      await _swipeNext(tester);
      await _swipeNext(tester);
      await _swipeNext(tester, delta: const Offset(300, 0));

      expect(pages, [1, 2, 1]);
    });

    testWidgets('isCurrentPage is true only for the visible page', (
      tester,
    ) async {
      await _pump(
        tester,
        _builder(_Tracker(), controller: PageController(initialPage: 3)),
      );

      expect(find.text('3:current'), findsOneWidget);
      expect(find.text('2:preloaded', skipOffstage: false), findsOneWidget);
      expect(find.text('4:preloaded', skipOffstage: false), findsOneWidget);
    });

    testWidgets('isCurrentPage updates after a swipe', (tester) async {
      await _pump(tester, _builder(_Tracker()));

      await _swipeNext(tester);

      expect(find.text('0:preloaded', skipOffstage: false), findsOneWidget);
      expect(find.text('1:current'), findsOneWidget);
      expect(find.text('2:preloaded', skipOffstage: false), findsOneWidget);
    });

    testWidgets('dragging within a page rebuilds nothing', (tester) async {
      final tracker = _Tracker();
      await _pump(
        tester,
        _builder(
          tracker,
          preload: 3,
          controller: PageController(initialPage: 5),
        ),
      );
      final before = Map.of(tracker.builds);

      // Less than half a page: the current page doesn't change.
      await tester.drag(find.byType(PreloadedPageView), const Offset(-100, 0));
      await tester.pump();

      for (final i in before.keys) {
        expect(tracker.builds[i], before[i], reason: 'page $i rebuilt');
      }
    });

    testWidgets('a page change rebuilds only the two pages that flipped', (
      tester,
    ) async {
      final tracker = _Tracker();
      await _pump(
        tester,
        _builder(
          tracker,
          preload: 3,
          controller: PageController(initialPage: 5),
        ),
      );
      final before = Map.of(tracker.builds);

      await _swipeNext(tester);

      final rebuilt = [
        for (final i in before.keys)
          if (tracker.builds[i] != before[i]) i,
      ]..sort();
      expect(rebuilt, [5, 6]);
    });

    testWidgets('indexOf works with the children constructor', (tester) async {
      final seen = <int?>[];
      await _pump(
        tester,
        PreloadedPageView(
          preloadPagesCount: 2,
          children: [
            for (var i = 0; i < 3; i++)
              Builder(
                builder: (context) {
                  seen.add(PreloadedPageView.indexOf(context));
                  return const SizedBox();
                },
              ),
          ],
        ),
      );

      expect(seen, [0, 1, 2]);
    });

    testWidgets('isCurrentPage is false outside a page', (tester) async {
      bool? result;
      await _pump(
        tester,
        Builder(
          builder: (context) {
            result = PreloadedPageView.isCurrentPage(context);
            return const SizedBox();
          },
        ),
      );

      expect(result, isFalse);
    });
  });

  group('exactness', () {
    testWidgets('exactly N pages either side for any viewportFraction', (
      tester,
    ) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = _size;
      addTearDown(tester.view.reset);
      bool onScreen(Rect r) => r.right > 0.5 && r.left < _size.width - 0.5;

      for (final padEnds in [true, false]) {
        for (final fraction in [1.0, 0.9, 0.8, 0.6, 0.5, 0.4, 0.25]) {
          for (final n in [1, 2, 4]) {
            final built = <int>{};
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.ltr,
                child: PreloadedPageView.builder(
                  preloadPagesCount: n,
                  padEnds: padEnds,
                  controller: PageController(
                    viewportFraction: fraction,
                    initialPage: 10,
                  ),
                  itemCount: 40,
                  itemBuilder: (context, i) {
                    built.add(i);
                    return Text('$i');
                  },
                ),
              ),
            );
            final visible = [
              for (final i in built)
                if (onScreen(
                  tester.getRect(find.text('$i', skipOffstage: false)),
                ))
                  i,
            ]..sort();
            final config = 'padEnds=$padEnds fraction=$fraction n=$n';
            expect(
              built.where((i) => i < visible.first).length,
              n,
              reason: config,
            );
            expect(
              built.where((i) => i > visible.last).length,
              n,
              reason: config,
            );
          }
        }
      }
    });

    testWidgets('pages sit exactly where PageView puts them', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = _size;
      addTearDown(tester.view.reset);

      Future<List<Rect>> layout(
        bool preloaded,
        double fraction,
        bool padEnds,
        int page,
      ) async {
        final controller = PageController(
          viewportFraction: fraction,
          initialPage: page,
        );
        Widget item(BuildContext context, int i) =>
            SizedBox.expand(key: ValueKey(i));
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: preloaded
                ? PreloadedPageView.builder(
                    controller: controller,
                    padEnds: padEnds,
                    itemCount: 10,
                    itemBuilder: item,
                  )
                : PageView.builder(
                    controller: controller,
                    padEnds: padEnds,
                    itemCount: 10,
                    itemBuilder: item,
                  ),
          ),
        );
        return [
          for (var i = 0; i < 10; i++)
            if (find.byKey(ValueKey(i)).evaluate().isNotEmpty)
              tester.getRect(find.byKey(ValueKey(i))),
        ];
      }

      for (final padEnds in [true, false]) {
        for (final fraction in [1.0, 0.8, 0.5]) {
          for (final page in [0, 4, 9]) {
            final ours = await layout(true, fraction, padEnds, page);
            final theirs = await layout(false, fraction, padEnds, page);
            expect(
              ours,
              theirs,
              reason: 'padEnds=$padEnds fraction=$fraction page=$page',
            );
          }
        }
      }
    });
  });

  group('behaves like PageView', () {
    testWidgets('snaps to pages', (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);
      await _pump(tester, _builder(_Tracker(), controller: controller));

      await tester.drag(find.byType(PreloadedPageView), const Offset(-250, 0));
      await tester.pumpAndSettle();

      expect(controller.page, 1);
    });

    testWidgets('pageSnapping: false stops anywhere', (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        PreloadedPageView.builder(
          controller: controller,
          pageSnapping: false,
          itemCount: 5,
          itemBuilder: (context, i) => Text('$i'),
        ),
      );

      await tester.drag(find.byType(PreloadedPageView), const Offset(-120, 0));
      await tester.pumpAndSettle();

      expect(controller.page, isNot(anyOf(0.0, 1.0)));
    });

    testWidgets('lets screen readers reach preloaded pages', (tester) async {
      await _pump(tester, _builder(_Tracker(), preload: 2));
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      expect(position.physics.allowImplicitScrolling, isTrue);
    });

    testWidgets('disposes its own controller', (tester) async {
      await _pump(tester, _builder(_Tracker()));
      await _pump(tester, const SizedBox());
      // Would throw "A PageController was used after being disposed" or leak
      // under leak tracking if we got this wrong.
      expect(tester.takeException(), isNull);
    });
  });
}
