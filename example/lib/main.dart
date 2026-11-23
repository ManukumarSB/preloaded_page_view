// Flutter 3.47 moved Material to package:material_ui, but that package needs
// Flutter >=3.47 and we still support 3.32. Switch once the floor gets there.
// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:preloaded_page_view/preloaded_page_view.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'preloaded_page_view',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      home: const FeedPage(),
    );
  }
}

/// A reels-style feed. Each clip pretends to buffer for a moment when it's
/// first built, like a real video would. Try preload 0, then 2.
class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  static const _clipCount = 30;

  int _preload = 2;
  final _alive = ValueNotifier<Set<int>>({});

  @override
  void dispose() {
    _alive.dispose();
    super.dispose();
  }

  void _setAlive(int index, bool alive) {
    // Called from initState/dispose of pages, which happen during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final next = {..._alive.value};
      alive ? next.add(index) : next.remove(index);
      _alive.value = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Preload'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('0')),
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
              ],
              selected: {_preload},
              onSelectionChanged: (s) => setState(() => _preload = s.first),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          PreloadedPageView.builder(
            scrollDirection: Axis.vertical,
            preloadPagesCount: _preload,
            itemCount: _clipCount,
            itemBuilder: (context, index) => FeedClip(
              index: index,
              onAlive: (alive) => _setAlive(index, alive),
            ),
          ),
          Positioned(
            right: 12,
            top: 0,
            bottom: 0,
            child: Center(
              child: _AliveStrip(alive: _alive, count: _clipCount),
            ),
          ),
        ],
      ),
    );
  }
}

/// One feed item. Stands in for a video player.
class FeedClip extends StatefulWidget {
  const FeedClip({super.key, required this.index, required this.onAlive});

  final int index;
  final ValueChanged<bool> onAlive;

  @override
  State<FeedClip> createState() => _FeedClipState();
}

class _FeedClipState extends State<FeedClip>
    with SingleTickerProviderStateMixin {
  bool _ready = false;
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void initState() {
    super.initState();
    widget.onAlive(true);
    // Pretend to buffer. With preloading, this happens off screen.
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    widget.onAlive(false);
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only the clip on screen plays; preloaded ones wait, ready.
    final playing = _ready && PreloadedPageView.isCurrentPage(context);
    if (playing && !_progress.isAnimating) {
      _progress.repeat();
    } else if (!playing && _progress.isAnimating) {
      _progress.reset();
    }

    final hue = (widget.index * 47) % 360;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.35).toColor(),
            HSLColor.fromAHSL(1, (hue + 40) % 360, 0.6, 0.15).toColor(),
          ],
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _ready
                  ? Text(
                      'Clip ${widget.index + 1}',
                      key: const ValueKey('ready'),
                      style: Theme.of(context).textTheme.displaySmall,
                    )
                  : const Column(
                      key: ValueKey('loading'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Buffering…'),
                      ],
                    ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: AnimatedBuilder(
                animation: _progress,
                builder: (context, _) => LinearProgressIndicator(
                  value: _progress.value,
                  minHeight: 3,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dots on the right edge: bright = alive (built), dim = not built.
class _AliveStrip extends StatelessWidget {
  const _AliveStrip({required this.alive, required this.count});

  final ValueListenable<Set<int>> alive;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<Set<int>>(
      valueListenable: alive,
      builder: (context, set, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(vertical: 2),
              width: 6,
              height: set.contains(i) ? 14 : 6,
              decoration: BoxDecoration(
                color: set.contains(i) ? color : Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}
