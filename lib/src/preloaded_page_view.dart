import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A [PageView] that builds pages ahead of time.
///
/// Pages within [preloadPagesCount] of the current page are built and laid
/// out before the user swipes to them, so a video can start buffering or an
/// image can start decoding while it is still off screen. Pages further away
/// are disposed, same as a normal [PageView].
///
/// ```dart
/// PreloadedPageView.builder(
///   preloadPagesCount: 2,
///   itemCount: videos.length,
///   itemBuilder: (context, index) => VideoPage(videos[index]),
/// )
/// ```
///
/// Preloading works in both directions: with `preloadPagesCount: 2` and the
/// user on page 5, pages 3 to 7 are alive.
///
/// Uses a regular [PageController], so anything that already works with a
/// [PageView] (page indicators, `animateToPage`, `jumpToPage`) works here.
///
/// To tell whether a page is the one on screen — say, to only play the
/// current video — use [PreloadedPageView.isCurrentPage] from inside the page.
class PreloadedPageView extends StatefulWidget {
  /// Creates a preloading page view from an explicit list of [children].
  ///
  /// All children are created up front, so prefer
  /// [PreloadedPageView.builder] for long or unbounded lists.
  PreloadedPageView({
    super.key,
    this.preloadPagesCount = 1,
    this.scrollDirection = Axis.horizontal,
    this.reverse = false,
    this.controller,
    this.physics,
    this.pageSnapping = true,
    this.onPageChanged,
    List<Widget> children = const <Widget>[],
    this.dragStartBehavior = DragStartBehavior.start,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    this.scrollBehavior,
    this.padEnds = true,
  }) : assert(preloadPagesCount >= 0),
       childrenDelegate = SliverChildListDelegate(<Widget>[
         for (var i = 0; i < children.length; i++)
           _PageIndex(index: i, child: children[i]),
       ]);

  /// Creates a preloading page view that builds pages on demand.
  ///
  /// [itemBuilder] is called for the current page and the
  /// [preloadPagesCount] pages on either side of it.
  ///
  /// If [itemCount] is null the page view scrolls forever.
  PreloadedPageView.builder({
    super.key,
    this.preloadPagesCount = 1,
    this.scrollDirection = Axis.horizontal,
    this.reverse = false,
    this.controller,
    this.physics,
    this.pageSnapping = true,
    this.onPageChanged,
    required NullableIndexedWidgetBuilder itemBuilder,
    ChildIndexGetter? findChildIndexCallback,
    int? itemCount,
    this.dragStartBehavior = DragStartBehavior.start,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    this.scrollBehavior,
    this.padEnds = true,
  }) : assert(preloadPagesCount >= 0),
       childrenDelegate = SliverChildBuilderDelegate(
         (context, index) {
           final page = itemBuilder(context, index);
           return page == null ? null : _PageIndex(index: index, child: page);
         },
         findChildIndexCallback: findChildIndexCallback,
         childCount: itemCount,
       );

  /// Creates a preloading page view with a custom [childrenDelegate].
  ///
  /// [PreloadedPageView.isCurrentPage] and [PreloadedPageView.indexOf] only
  /// work for pages built by the other two constructors.
  const PreloadedPageView.custom({
    super.key,
    this.preloadPagesCount = 1,
    this.scrollDirection = Axis.horizontal,
    this.reverse = false,
    this.controller,
    this.physics,
    this.pageSnapping = true,
    this.onPageChanged,
    required this.childrenDelegate,
    this.dragStartBehavior = DragStartBehavior.start,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    this.scrollBehavior,
    this.padEnds = true,
  }) : assert(preloadPagesCount >= 0);

  /// How many pages to keep built on each side of the current page.
  ///
  /// `0` behaves like a plain [PageView]: only visible pages exist. Each extra
  /// page costs memory, so keep this small for heavy pages like videos.
  final int preloadPagesCount;

  /// The axis along which the page view scrolls.
  final Axis scrollDirection;

  /// Whether the page view scrolls in the reading direction.
  ///
  /// See [PageView.reverse].
  final bool reverse;

  /// Controls which page is visible.
  ///
  /// If null, the page view creates and disposes its own [PageController].
  final PageController? controller;

  /// How the page view responds to user input.
  ///
  /// Combined with [PageScrollPhysics] when [pageSnapping] is true.
  final ScrollPhysics? physics;

  /// Whether to snap to page boundaries after a drag.
  final bool pageSnapping;

  /// Called whenever the page in the center of the viewport changes.
  final ValueChanged<int>? onPageChanged;

  /// Supplies the pages.
  final SliverChildDelegate childrenDelegate;

  /// See [Scrollable.dragStartBehavior].
  final DragStartBehavior dragStartBehavior;

  /// See [Scrollable.restorationId].
  final String? restorationId;

  /// How to clip pages that are partly outside the viewport.
  final Clip clipBehavior;

  /// A [ScrollBehavior] used for this page view only.
  ///
  /// Scrollbars are turned off by default, as in [PageView].
  final ScrollBehavior? scrollBehavior;

  /// Whether to add padding at both ends when
  /// [PageController.viewportFraction] is below 1.
  final bool padEnds;

  /// Whether the page that [context] belongs to is the current page.
  ///
  /// The calling widget rebuilds when the current page changes. Use it to
  /// start and stop work that should only happen on screen:
  ///
  /// ```dart
  /// final playing = PreloadedPageView.isCurrentPage(context);
  /// playing ? controller.play() : controller.pause();
  /// ```
  ///
  /// Returns false when [context] isn't inside a page built by
  /// [PreloadedPageView] or [PreloadedPageView.builder].
  static bool isCurrentPage(BuildContext context) {
    final index = indexOf(context);
    if (index == null) return false;
    // Depend on this page's index only, so a page change rebuilds the page
    // that left and the page that arrived — not every preloaded page.
    final current = InheritedModel.inheritFrom<_CurrentPage>(
      context,
      aspect: index,
    );
    return current?.page == index;
  }

  /// The index of the page that [context] belongs to, or null if [context]
  /// isn't inside a page built by [PreloadedPageView] or
  /// [PreloadedPageView.builder].
  static int? indexOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<_PageIndex>()?.index;
  }

  @override
  State<PreloadedPageView> createState() => _PreloadedPageViewState();
}

class _PreloadedPageViewState extends State<PreloadedPageView> {
  late PageController _controller;
  late final ValueNotifier<int> _currentPage;

  PageController get _effectiveController => widget.controller ?? _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    final controller = _effectiveController;
    _currentPage = ValueNotifier<int>(
      controller.hasClients && controller.position.haveDimensions
          ? controller.page!.round()
          : controller.initialPage,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _currentPage.dispose();
    super.dispose();
  }

  AxisDirection _axisDirection(BuildContext context) {
    switch (widget.scrollDirection) {
      case Axis.horizontal:
        final direction = textDirectionToAxisDirection(
          Directionality.of(context),
        );
        return widget.reverse ? flipAxisDirection(direction) : direction;
      case Axis.vertical:
        return widget.reverse ? AxisDirection.up : AxisDirection.down;
    }
  }

  /// How far past the viewport to build, in viewports.
  ///
  /// This is the whole trick: PageView hard-codes it to 0 or 1 viewport
  /// (flutter/flutter#45632). One page is [fraction] of a viewport, so N
  /// pages is N * fraction.
  double _cacheExtent(double fraction) => widget.preloadPagesCount * fraction;

  bool _handleScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification is! ScrollUpdateNotification) {
      return false;
    }
    final page = (notification.metrics as PageMetrics).page;
    if (page == null) return false;

    final rounded = page.round();
    if (rounded != _currentPage.value) {
      _currentPage.value = rounded;
      widget.onPageChanged?.call(rounded);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _effectiveController;
    final axisDirection = _axisDirection(context);
    final base =
        widget.physics ?? widget.scrollBehavior?.getScrollPhysics(context);

    // Implicit scrolling lets screen readers move focus onto a preloaded page
    // and scroll it into view, which PageView only allows for one page.
    final physics =
        _ImplicitScrollPhysics(
          allowImplicitScrolling: widget.preloadPagesCount > 0,
        ).applyTo(
          widget.pageSnapping ? const PageScrollPhysics().applyTo(base) : base,
        );

    final pad = widget.padEnds && controller.viewportFraction < 1;

    return ValueListenableBuilder<int>(
      valueListenable: _currentPage,
      builder: (context, page, child) =>
          _CurrentPage(page: page, child: child!),
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScroll,
        child: Scrollable(
          dragStartBehavior: widget.dragStartBehavior,
          axisDirection: axisDirection,
          controller: controller,
          physics: physics,
          restorationId: widget.restorationId,
          scrollBehavior:
              widget.scrollBehavior ??
              ScrollConfiguration.of(context).copyWith(scrollbars: false),
          viewportBuilder: (context, position) {
            return Viewport(
              cacheExtent: _cacheExtent(controller.viewportFraction),
              cacheExtentStyle: CacheExtentStyle.viewport,
              axisDirection: axisDirection,
              offset: position,
              clipBehavior: widget.clipBehavior,
              slivers: <Widget>[
                // padEnds is done with spacer slivers rather than
                // SliverFillViewport(padEnds: true). Its padding wrapper
                // shifts the cache window, which leaves the leading side a
                // page short and the trailing side pages long.
                if (pad) _EndSpacer(fraction: controller.viewportFraction),
                SliverFillViewport(
                  viewportFraction: controller.viewportFraction,
                  delegate: widget.childrenDelegate,
                  padEnds: false,
                ),
                if (pad) _EndSpacer(fraction: controller.viewportFraction),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Empty space of half the leftover viewport, so the first and last page can
/// sit in the middle — what `padEnds` does in a [PageView].
class _EndSpacer extends StatelessWidget {
  const _EndSpacer({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final extent = constraints.viewportMainAxisExtent * (1 - fraction) / 2;
        final vertical = constraints.axis == Axis.vertical;
        return SliverToBoxAdapter(
          child: SizedBox(
            width: vertical ? null : extent,
            height: vertical ? extent : null,
          ),
        );
      },
    );
  }
}

class _ImplicitScrollPhysics extends ScrollPhysics {
  const _ImplicitScrollPhysics({
    required this.allowImplicitScrolling,
    super.parent,
  });

  @override
  final bool allowImplicitScrolling;

  @override
  _ImplicitScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _ImplicitScrollPhysics(
      allowImplicitScrolling: allowImplicitScrolling,
      parent: buildParent(ancestor),
    );
  }
}

class _CurrentPage extends InheritedModel<int> {
  const _CurrentPage({required this.page, required super.child});

  final int page;

  @override
  bool updateShouldNotify(_CurrentPage oldWidget) => page != oldWidget.page;

  @override
  bool updateShouldNotifyDependent(
    _CurrentPage oldWidget,
    Set<int> dependencies,
  ) {
    return dependencies.contains(page) || dependencies.contains(oldWidget.page);
  }
}

class _PageIndex extends InheritedWidget {
  const _PageIndex({required this.index, required super.child});

  final int index;

  @override
  bool updateShouldNotify(_PageIndex oldWidget) => index != oldWidget.index;
}
