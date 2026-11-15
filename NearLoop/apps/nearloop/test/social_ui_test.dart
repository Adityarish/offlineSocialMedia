import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_store/local_store.dart';
import 'package:protocol/protocol.dart';
import '../lib/controller.dart';
import '../lib/main.dart';
import '../lib/social_widgets.dart';

void main() {
  late AppController app;
  late Directory temp;
  late String postId;
  setUp(() async {
    app = AppController();
    temp = await Directory.systemTemp.createTemp('nearloop-ui-');
    app.directory = temp;
    app.repo = await LocalRepository.open('${temp.path}/test.sqlite');
    app.identity = await DeviceIdentity.create();
    app.name = 'Alex Morgan';
    app.bio = 'Finding the lovely in the everyday.';
    app.spaceId = randomId();
    postId = randomId();
    await app.repo.addSpace(
      app.spaceId!,
      'The weekend circle',
      app.identity.id,
    );
    await app.repo.db.insert('memberships', {
      'space': app.spaceId,
      'actor': app.identity.id,
      'name': app.name,
      'role': 'host',
    });
    await app.repo.commit(app.spaceId!, app.identity.id, {
      'v': 1,
      'id': randomId(),
      'space': app.spaceId,
      'actor': app.identity.id,
      'op': 'post.create',
      'entity': postId,
      'revision': 0,
      'payload': {
        'text':
            'Slow mornings. Good company. A little more of this, please. #weekend',
        'media': [],
      },
      'clientTime': 0,
    });
    app.members = [
      {'actor': app.identity.id, 'name': app.name, 'seen': 0},
    ];
    await app.refresh();
  });
  tearDown(() async {
    app.timer?.cancel();
    app.dispose();
    await app.repo.close();
    await temp.delete(recursive: true);
  });

  test(
    'offline reactions follow queued intent and bookmarks persist',
    () async {
      await app.toggleLike(postId);
      expect(app.social[postId]!['liked'], true);
      expect(app.social[postId]!['likes'], 1);
      await app.toggleLike(postId);
      expect(app.social[postId]!['liked'], false);
      expect(app.social[postId]!['likes'], 0);
      await app.bookmark(postId);
      await app.refresh();
      expect(app.social[postId]!['saved'], true);
      expect(app.pending.length, 2);
    },
  );

  testWidgets(
    'phone feed, profile, saved grid and composer render without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: NearLoop(app)),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your feed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, boundary, 'feed-phone');
      await tester.tap(find.byTooltip('Profile'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your own little corner.'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'Profile must fit the phone',
      );
      await screenshot(tester, boundary, 'profile-phone');
      tester.view.physicalSize = const Size(320, 700);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Profile must fit a narrow phone',
      );
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Keep the good ones.'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'Saved grid must fit the phone',
      );
      await tester.tap(find.byTooltip('Create'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();
      expect(find.text('A new moment.'), findsOneWidget);
      await screenshot(tester, boundary, 'composer-phone');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'comments keep offline submissions visible and prevent empty posts',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: nearLoopTheme(),
          home: Scaffold(
            body: CommentsSheet(app: app, post: app.posts.first),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Start the conversation'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Post'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'What a lovely morning!');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Post'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Waiting to sync'), findsOneWidget);
      expect(find.text('What a lovely morning!'), findsOneWidget);
      expect(
        jsonDecode(app.pending.single['body'])['payload']['text'],
        'What a lovely morning!',
      );
      expect(tester.takeException(), isNull);
      final commentsBoundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: commentsBoundary,
          child: MaterialApp(
            theme: nearLoopTheme(),
            home: Scaffold(
              body: CommentsSheet(app: app, post: app.posts.first),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();
      await screenshot(tester, commentsBoundary, 'comments-phone');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('desktop navigation and narrow onboarding fit', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: boundary, child: NearLoop(app)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Good moments. Close by.'), findsOneWidget);
    await screenshot(tester, boundary, 'feed-desktop');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.name = '';
    tester.view.physicalSize = const Size(320, 700);
    await tester.pumpWidget(NearLoop(app));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Life happens nearby.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> screenshot(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  const output = String.fromEnvironment('NEARLOOP_SCREENSHOTS');
  if (output.isEmpty) return;
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
