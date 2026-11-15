import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:protocol/protocol.dart';
import 'controller.dart';
import 'social_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  try {
    await controller.initialize();
    runApp(NearLoop(controller));
  } catch (_) {
    runApp(
      MaterialApp(
        theme: nearLoopTheme(),
        home: const Scaffold(
          body: Center(
            child: EmptyMoment(
              icon: Icons.lock_outline,
              title: 'Let’s get you back in',
              message:
                  'NearLoop could not open local storage or the system key store. Check disk space and platform keychain configuration, then restart. Your existing data has not been reset.',
            ),
          ),
        ),
      ),
    );
  }
}

ThemeData nearLoopTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: accent,
    primary: accent,
    surface: Colors.white,
    onSurface: ink,
  ),
  scaffoldBackgroundColor: Colors.white,
  dividerColor: line,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: ink,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: ink),
    bodySmall: TextStyle(color: muted, fontSize: 12),
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -.6,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: canvas,
    contentPadding: const EdgeInsets.all(16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: accent),
    ),
    hintStyle: const TextStyle(color: muted),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 46),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: ink,
      minimumSize: const Size(0, 44),
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(foregroundColor: ink),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
  ),
);

class NearLoop extends StatelessWidget {
  final AppController app;
  const NearLoop(this.app, {super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NearLoop',
    debugShowCheckedModeBanner: false,
    theme: nearLoopTheme(),
    home: Home(app),
  );
}

class Home extends StatefulWidget {
  final AppController app;
  const Home(this.app, {super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  AppController get a => widget.app;
  int tab = 0;
  bool savedGrid = false, editingProfile = false, loadedDraft = false;
  final displayName = TextEditingController(),
      bio = TextEditingController(),
      caption = TextEditingController(),
      alt = TextEditingController(),
      joinText = TextEditingController(),
      spaceName = TextEditingController(text: 'Our nearby space'),
      searchInput = TextEditingController();
  final selected = <String>[];
  List<InternetAddress> addresses = [];
  InternetAddress? address;
  NativeDiscovery? discovery;
  StreamSubscription<Uri>? subscription;
  final Set<Uri> found = {};
  String discoveryStatus =
      'Find people sharing your Wi-Fi network. Ask your host for an invitation to join.';
  Timer? draftTimer;
  Future<void> draftWrites = Future<void>.value();
  static const labels = ['Home', 'Explore', 'Create', 'Activity', 'Profile'];
  static const icons = [
    Icons.home_outlined,
    Icons.search_rounded,
    Icons.add_box_outlined,
    Icons.favorite_border_rounded,
    Icons.person_outline_rounded,
  ];
  static const activeIcons = [
    Icons.home_rounded,
    Icons.search_rounded,
    Icons.add_box_rounded,
    Icons.favorite_rounded,
    Icons.person_rounded,
  ];
  @override
  void initState() {
    super.initState();
    displayName.text = a.name;
    bio.text = a.bio;
    a.addListener(changed);
    WidgetsBinding.instance.addObserver(this);
    _interfaces();
  }

  Future<void> _interfaces() async {
    try {
      final interfaces = await NetworkInterface.list(includeLoopback: true);
      if (!mounted) return;
      setState(() {
        addresses = interfaces
            .expand((i) => i.addresses)
            .where((i) => !i.isLinkLocal)
            .toList();
        address =
            addresses.where((i) => !i.isLoopback).firstOrNull ??
            addresses.firstOrNull;
      });
    } catch (_) {}
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) a.synchronize();
    if (state == AppLifecycleState.paused &&
        (Platform.isIOS || Platform.isAndroid)) {
      persistDraft();
      a.disconnect();
    }
  }

  @override
  void dispose() {
    draftTimer?.cancel();
    a.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    subscription?.cancel();
    discovery?.stop();
    for (final c in [
      displayName,
      bio,
      caption,
      alt,
      joinText,
      spaceName,
      searchInput,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> navigate(int index) async {
    FocusScope.of(context).unfocus();
    if (index == 2 && a.spaceId != null && !loadedDraft) {
      await a.run(() async {
        caption.clear();
        alt.clear();
        selected.clear();
        final rows = await a.repo.db.query(
          'drafts',
          where: 'space=?',
          whereArgs: [a.spaceId],
        );
        if (rows.isNotEmpty) {
          final d = jsonDecode(rows.first['body'] as String);
          caption.text = d['text'] ?? '';
          alt.text = d['alt'] ?? '';
          selected
            ..clear()
            ..addAll(List<String>.from(d['files'] ?? []));
        }
        loadedDraft = true;
      });
    }
    if (mounted)
      setState(() {
        tab = index;
        editingProfile = false;
      });
  }

  Future<void> action(Future<void> Function() fn, {String? success}) async {
    await a.run(fn);
    if (!mounted) return;
    final message = a.lastError ?? success;
    if (message != null)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Widget button(String text, IconData icon, Future<void> Function() fn) =>
      FilledButton.icon(
        onPressed: a.busy ? null : () => action(fn),
        icon: Icon(icon, size: 19),
        label: Text(text),
      );
  Widget panel(String title, String subtitle, List<Widget> children) =>
      Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(color: muted, height: 1.5)),
            const SizedBox(height: 22),
            ...children,
          ],
        ),
      );
  Widget brand() => const FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.blur_circular_rounded, color: accent, size: 29),
        SizedBox(width: 8),
        Text(
          'NearLoop',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.3,
          ),
        ),
      ],
    ),
  );
  Widget connectionBadge() => InkWell(
    onTap: () => navigate(5),
    borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: a.online ? const Color(0xffedf6f0) : canvas,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: a.online ? const Color(0xff3f8d60) : muted,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            a.online ? 'Nearby' : 'Offline',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final onboarding = a.name.isEmpty;
    final page = onboarding
        ? welcome()
        : switch (tab) {
            0 => feed(),
            1 => explore(),
            2 => composer(),
            3 => activity(),
            4 => profile(),
            _ => discover(),
          };
    return Scaffold(
      appBar: wide && !onboarding
          ? null
          : AppBar(
              title: brand(),
              actions: [
                connectionBadge(),
                const SizedBox(width: 4),
                if (!onboarding)
                  IconButton(
                    tooltip: 'Activity',
                    onPressed: () => navigate(3),
                    icon: Badge(
                      isLabelVisible: a.pending.isNotEmpty,
                      label: Text('${a.pending.length}'),
                      child: const Icon(Icons.favorite_border_rounded),
                    ),
                  ),
                const SizedBox(width: 8),
              ],
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(1),
                child: Divider(height: 1),
              ),
            ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide && !onboarding) sidebar(),
            Expanded(
              child: Column(
                children: [
                  if (a.busy) const LinearProgressIndicator(minHeight: 2),
                  if (a.lastError != null)
                    Material(
                      color: const Color(0xfffff1f3),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: accent,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                a.lastError!,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Dismiss message',
                              onPressed: () =>
                                  setState(() => a.lastError = null),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        await a.synchronize();
                        await a.refresh();
                      },
                      child: SingleChildScrollView(
                        key: PageStorageKey('page-$tab'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: tab == 0 ? 1020 : 760,
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: wide ? 32 : (tab == 0 ? 0 : 18),
                                vertical: wide ? 38 : 20,
                              ),
                              child: tab == 0 && wide && !onboarding
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: page),
                                        const SizedBox(width: 36),
                                        SizedBox(
                                          width: 240,
                                          child: sideNotes(),
                                        ),
                                      ],
                                    )
                                  : page,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide || onboarding
          ? null
          : DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: line)),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 62,
                  child: Row(
                    children: List.generate(
                      5,
                      (i) => Expanded(
                        child: Tooltip(
                          message: labels[i],
                          child: InkWell(
                            onTap: () => navigate(i),
                            child: Semantics(
                              selected: tab == i,
                              label: labels[i],
                              button: true,
                              child: Center(
                                child: i == 4
                                    ? Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: tab == 4
                                                ? ink
                                                : Colors.transparent,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: PersonAvatar(a.name, size: 25),
                                      )
                                    : i == 2
                                    ? Container(
                                        width: 40,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: ink,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.add,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        tab == i ? activeIcons[i] : icons[i],
                                        size: 27,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget sidebar() => Container(
    width: 224,
    padding: const EdgeInsets.fromLTRB(22, 38, 20, 24),
    decoration: const BoxDecoration(
      border: Border(right: BorderSide(color: line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        brand(),
        const SizedBox(height: 45),
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              selected: tab == i,
              selectedTileColor: const Color(0xfff8edef),
              selectedColor: ink,
              leading: i == 4
                  ? PersonAvatar(a.name, size: 26)
                  : Icon(tab == i ? activeIcons[i] : icons[i], size: 26),
              title: Text(
                labels[i],
                style: TextStyle(
                  fontWeight: tab == i ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              onTap: () => navigate(i),
            ),
          ),
        const Spacer(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.people_outline_rounded),
          title: const Text('Your space'),
          onTap: () => navigate(5),
        ),
        const Divider(height: 30),
        connectionBadge(),
        const SizedBox(height: 12),
        const Text(
          'Good moments. Close by.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    ),
  );
  Widget sideNotes() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          PersonAvatar(a.name, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Text(
                  'Your little corner',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          TextButton(onPressed: () => navigate(4), child: const Text('View')),
        ],
      ),
      const SizedBox(height: 32),
      const Text(
        'YOUR NEARBY SPACE',
        style: TextStyle(
          fontSize: 10,
          color: muted,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        a.spaceId == null ? 'Better, together.' : a.spaceTitle,
        style: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -.5,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        a.spaceId == null
            ? 'A private place for the people around you. Start a space and invite your circle.'
            : '${a.visibleMembers.length} people in your circle. Share moments over your local network.',
        style: const TextStyle(color: muted, height: 1.6, fontSize: 13),
      ),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: () => navigate(5),
        child: Text(a.spaceId == null ? 'Find your people' : 'Manage space'),
      ),
      const SizedBox(height: 32),
      const Divider(),
      const SizedBox(height: 16),
      const Text(
        'A little less scrolling.\nA little more connection.',
        style: TextStyle(
          fontSize: 19,
          height: 1.5,
          fontWeight: FontWeight.w500,
          letterSpacing: -.5,
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Private spaces · Original photos\nNo cloud account required',
        style: TextStyle(color: muted, fontSize: 11, height: 1.8),
      ),
    ],
  );
  Widget heading(String title, String subtitle, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.9,
                ),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: muted)),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    ),
  );
  Widget welcome() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 24),
      const Center(child: PersonAvatar('NearLoop', size: 94, ring: true)),
      const SizedBox(height: 28),
      const Text(
        'Life happens nearby.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.3,
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Share the everyday with your people.\nYour photos, your circle, your own little world.',
        textAlign: TextAlign.center,
        style: TextStyle(color: muted, height: 1.7),
      ),
      const SizedBox(height: 32),
      panel(
        'Make yourself at home',
        'Start with a name your friends will recognize.',
        [
          TextField(
            controller: displayName,
            textCapitalization: TextCapitalization.words,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Your name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: bio,
            maxLength: 300,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'A little about you',
              hintText: 'The things that make you, you.',
            ),
          ),
          const SizedBox(height: 12),
          button('Join the loop', Icons.arrow_forward_rounded, () async {
            await a.profile(displayName.text.trim(), bio.text.trim());
            if (mounted) setState(() => tab = 5);
          }),
        ],
      ),
      const Text(
        'No email or phone number. Your profile stays on this device.\nShared moments are copied to members of your space.',
        textAlign: TextAlign.center,
        style: TextStyle(color: muted, fontSize: 12, height: 1.7),
      ),
    ],
  );
  Widget feed() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Your feed',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.7,
                ),
              ),
            ),
            TextButton(
              onPressed: () => navigate(5),
              child: Row(
                children: [
                  const Icon(Icons.people_outline, size: 17),
                  const SizedBox(width: 5),
                  Text(a.spaceId == null ? 'Find a space' : 'Your space'),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 104,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          children: [
            InkWell(
              onTap: () => navigate(2),
              child: SizedBox(
                width: 78,
                child: Column(
                  children: [
                    Stack(
                      children: [
                        PersonAvatar(a.name, size: 64),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.add,
                              size: 21,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('Your moment', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
            for (final member
                in a.visibleMembers
                    .where((m) => m['actor'] != a.identity.id)
                    .take(12))
              InkWell(
                onTap: () => showMember(member['actor']),
                child: SizedBox(
                  width: 78,
                  child: Column(
                    children: [
                      PersonAvatar(
                        a.nameFor(member['actor']),
                        size: 64,
                        ring: true,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        a.nameFor(member['actor']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            if (a.visibleMembers.length <= 1)
              InkWell(
                onTap: () => navigate(5),
                child: SizedBox(
                  width: 78,
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: line, width: 2),
                        ),
                        child: const Icon(
                          Icons.person_add_alt_1_outlined,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Invite people',
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      const Divider(height: 1),
      if (a.spaceId == null)
        EmptyMoment(
          icon: Icons.people_outline_rounded,
          title: 'Find your people.',
          message:
              'The best moments are the ones you share.\nJoin a nearby space or make one of your own.',
          action: 'Explore nearby spaces',
          onAction: () => navigate(5),
        )
      else if (a.posts.isEmpty)
        EmptyMoment(
          icon: Icons.photo_camera_outlined,
          title: 'Every circle starts somewhere.',
          message:
              'A photo, a thought, a little hello.\nShare the first moment in ${a.spaceTitle}.',
          action: 'Create your first post',
          onAction: () => navigate(2),
        ),
      for (final post in a.posts) postCard(post),
      if (a.posts.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: OutlinedButton(
            onPressed: a.busy
                ? null
                : () => action(() => a.refresh(more: true)),
            child: const Text('Earlier moments'),
          ),
        ),
    ],
  );
  Future<void> showMember(String actor) async {
    if (actor == a.identity.id) {
      await navigate(4);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PersonAvatar(a.nameFor(actor), size: 82, ring: true),
              const SizedBox(height: 16),
              Text(
                a.nameFor(actor),
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                a.profiles[actor]?['bio'] ?? 'Part of your nearby circle.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Back to your feed'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget postCard(Json post) {
    final data = post['data'] as Json;
    final owner = a.nameFor(post['actor']);
    final stats = a.social[post['id']] ?? {};
    final images = List<String>.from(data['media'] ?? []);
    final liked = stats['liked'] == true, saved = stats['saved'] == true;
    return Container(
      key: ValueKey(post['id']),
      margin: const EdgeInsets.only(bottom: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 6, 14),
            child: Row(
              children: [
                InkWell(
                  onTap: () => showMember(post['actor']),
                  child: PersonAvatar(owner, size: 38, ring: true),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => showMember(post['actor']),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          owner,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          a.spaceTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Post options',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (v) => postAction(v, post),
                  itemBuilder: (_) => [
                    if (post['actor'] == a.identity.id) ...[
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit caption'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete post'),
                      ),
                    ] else ...[
                      const PopupMenuItem(
                        value: 'block',
                        child: Text('Block this person locally'),
                      ),
                      if (a.host != null)
                        const PopupMenuItem(
                          value: 'moderate',
                          child: Text('Remove from space'),
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (images.isNotEmpty)
            PhotoCarousel(
              key: ValueKey('photos-${post['id']}'),
              app: a,
              images: images,
              alt: data['alt'] ?? '',
              onLike: () {
                if (!liked) action(() => a.toggleLike(post['id']));
              },
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              constraints: const BoxConstraints(minHeight: 180),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xfffcf0e9), Color(0xfff3edf7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                data['text'] ?? '',
                style: const TextStyle(
                  fontSize: 23,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -.5,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 4, 7, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: liked ? 'Unlike post' : 'Like post',
                  onPressed: a.busy
                      ? null
                      : () => action(() => a.toggleLike(post['id'])),
                  icon: Icon(
                    liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: liked ? accent : ink,
                    size: 27,
                  ),
                ),
                IconButton(
                  tooltip: 'Comments',
                  onPressed: () => comments(post),
                  icon: const Icon(Icons.mode_comment_outlined, size: 25),
                ),
                IconButton(
                  tooltip: 'Copy post text',
                  onPressed: () => action(
                    () => Clipboard.setData(
                      ClipboardData(
                        text: '${data['text'] ?? ''}\n— $owner · NearLoop',
                      ),
                    ),
                    success: 'Post text copied',
                  ),
                  icon: const Icon(Icons.send_outlined, size: 25),
                ),
                const Spacer(),
                IconButton(
                  tooltip: saved ? 'Remove from saved' : 'Save post',
                  onPressed: a.busy
                      ? null
                      : () => action(() => a.bookmark(post['id'])),
                  icon: Icon(
                    saved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    size: 27,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${stats['likes'] ?? 0} ${(stats['likes'] ?? 0) == 1 ? 'like' : 'likes'}${stats['pending'] == true ? ' · waiting to sync' : ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (images.isNotEmpty &&
                    (data['text'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$owner  ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: data['text']),
                      ],
                    ),
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => comments(post),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(
                      (stats['comments'] ?? 0) == 0
                          ? 'Be the first to comment'
                          : 'View all ${stats['comments']} comments',
                      style: const TextStyle(color: muted, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                InkWell(
                  onTap: () => comments(post),
                  child: Row(
                    children: [
                      PersonAvatar(a.name, size: 23),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Add a comment…',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                      const Icon(
                        Icons.sentiment_satisfied_alt,
                        color: muted,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> comments(Json post) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => CommentsSheet(app: a, post: post),
  );
  Future<void> postAction(String value, Json post) async {
    if (value == 'edit') {
      final text = await askText('Edit caption', initial: post['data']['text']);
      if (text != null)
        await action(
          () => a.enqueue('post.edit', post['id'], {
            'text': text,
          }, revision: post['revision']),
        );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          value == 'block' ? 'Block this person?' : 'Remove this post?',
        ),
        content: Text(
          value == 'block'
              ? 'Their posts and comments will be hidden on this device.'
              : 'This removes the post from your space. Copies already saved by other people may remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(value == 'block' ? 'Block' : 'Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await action(() async {
      if (value == 'block') {
        await a.block(post['actor']);
      } else {
        await a.enqueue(
          value == 'moderate' ? 'post.moderate' : 'post.delete',
          post['id'],
          {},
          revision: post['revision'],
        );
      }
    });
  }

  Future<String?> askText(String title, {String initial = ''}) async {
    final input = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: input, maxLines: 5, maxLength: 4000),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, input.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // The dialog route may still be animating out, so defer controller disposal.
    Future<void>.delayed(const Duration(milliseconds: 350), input.dispose);
    return result;
  }

  Widget explore() {
    final term = searchInput.text.trim().toLowerCase();
    final posts = a.explorePosts
        .where(
          (p) =>
              term.isEmpty ||
              '${p['data']['text']} ${a.nameFor(p['actor'])}'
                  .toLowerCase()
                  .contains(term),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('A little discovery.', 'Moments from your nearby circle.'),
        TextField(
          controller: searchInput,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search people, captions, #hashtags',
            suffixIcon: searchInput.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () => setState(searchInput.clear),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Icon(Icons.wifi_rounded, size: 16, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                a.spaceId == null
                    ? 'Your next connection is close by.'
                    : a.spaceTitle,
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ),
            TextButton(
              onPressed: () => navigate(5),
              child: const Text('Find a space'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (posts.isEmpty)
          EmptyMoment(
            icon: Icons.search_rounded,
            title: term.isEmpty
                ? 'Something good is nearby.'
                : 'No moments found',
            message: term.isEmpty
                ? 'Join a space to explore photos and posts shared by your people.'
                : 'Try another name, word, or hashtag.',
            action: term.isEmpty ? 'Explore spaces' : null,
            onAction: () => navigate(5),
          )
        else
          postGrid(posts),
      ],
    );
  }

  Widget postGrid(List<Json> posts) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: posts.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      crossAxisSpacing: 3,
      mainAxisSpacing: 3,
    ),
    itemBuilder: (_, i) {
      final p = posts[i], data = p['data'] as Json;
      final images = List<String>.from(data['media'] ?? []);
      return Semantics(
        label: 'Open post by ${a.nameFor(p['actor'])}',
        button: true,
        child: InkWell(
          onTap: () => showPost(p),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (images.isNotEmpty)
                MediaTile(
                  a,
                  images.first,
                  data['alt'] ?? '',
                  compact: true,
                  key: ValueKey('${a.spaceId}-${p['id']}-${images.first}'),
                )
              else
                Container(
                  color: i.isEven
                      ? const Color(0xfff4e9e3)
                      : const Color(0xffe9e8f0),
                  padding: const EdgeInsets.all(14),
                  alignment: Alignment.center,
                  child: Text(
                    data['text'] ?? '',
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (images.length > 1)
                const Positioned(
                  right: 8,
                  top: 8,
                  child: Icon(
                    Icons.collections_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
  Future<void> showPost(Json post) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 620),
    builder: (ctx) => AnimatedBuilder(
      animation: a,
      builder: (_, __) {
        final current = a.explorePosts
            .where((p) => p['id'] == post['id'])
            .firstOrNull;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * .9,
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 20),
                    const Expanded(
                      child: Text(
                        'Post',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close post',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: current == null
                        ? const EmptyMoment(
                            icon: Icons.hide_image_outlined,
                            title: 'Post unavailable',
                            message:
                                'This post was removed or is no longer visible.',
                          )
                        : postCard(current),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  Widget profile() {
    final posts = savedGrid
        ? a.explorePosts
              .where((p) => a.social[p['id']]?['saved'] == true)
              .toList()
        : a.profilePosts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          a.name,
          'Your own little corner.',
          trailing: IconButton(
            tooltip: 'Profile settings',
            onPressed: () => setState(() => editingProfile = !editingProfile),
            icon: const Icon(Icons.tune_rounded),
          ),
        ),
        Row(
          children: [
            PersonAvatar(a.name, size: 88, ring: true),
            const SizedBox(width: 22),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(child: stat('${a.profilePosts.length}', 'posts')),
                  Expanded(
                    child: stat('${a.visibleMembers.length}', 'in your circle'),
                  ),
                  Expanded(
                    child: stat(
                      '${a.social.values.where((s) => s['saved'] == true).length}',
                      'saved',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(a.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (a.bio.isNotEmpty) ...[const SizedBox(height: 4), Text(a.bio)],
        const SizedBox(height: 8),
        Text(
          a.spaceId == null ? 'Ready to find your circle' : a.spaceTitle,
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () =>
                    setState(() => editingProfile = !editingProfile),
                child: Text(editingProfile ? 'Close settings' : 'Edit profile'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () => navigate(5),
                child: const Text('Your space'),
              ),
            ),
          ],
        ),
        if (editingProfile) ...[const SizedBox(height: 24), settings()],
        const SizedBox(height: 28),
        const Divider(height: 1),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: !savedGrid ? ink : muted,
                ),
                onPressed: () => setState(() => savedGrid = false),
                icon: const Icon(Icons.grid_on_rounded, size: 19),
                label: const Text('Posts'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: savedGrid ? ink : muted,
                ),
                onPressed: () => setState(() => savedGrid = true),
                icon: const Icon(Icons.bookmark_border_rounded, size: 20),
                label: const Text('Saved'),
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        const SizedBox(height: 4),
        if (posts.isEmpty)
          EmptyMoment(
            icon: savedGrid
                ? Icons.bookmark_border_rounded
                : Icons.photo_camera_outlined,
            title: savedGrid
                ? 'Keep the good ones.'
                : 'Your story starts here.',
            message: savedGrid
                ? 'Save posts you want to come back to.\nOnly you can see your saved collection.'
                : 'Share a photo or a thought with your circle.',
            action: savedGrid ? 'Explore your feed' : 'Share a moment',
            onAction: () => navigate(savedGrid ? 0 : 2),
          )
        else
          postGrid(posts),
      ],
    );
  }

  Widget stat(String value, String label) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: muted, fontSize: 11),
      ),
    ],
  );
  Future<void> saveDraft() async {
    require(a.spaceId != null, 'Join a space before saving a draft');
    final space = a.spaceId!;
    final body = jsonEncode({
      'text': caption.text,
      'alt': alt.text,
      'files': List<String>.of(selected),
    });
    draftWrites = draftWrites
        .catchError((Object _) {})
        .then(
          (_) => a.repo.db
              .rawInsert(
                'INSERT OR REPLACE INTO drafts(space,body) VALUES(?,?)',
                [space, body],
              )
              .then((_) {}),
        );
    await draftWrites;
  }

  void persistDraft() {
    draftTimer?.cancel();
    if (a.spaceId != null && loadedDraft) {
      saveDraft().catchError((Object e) {
        if (mounted) setState(() => a.lastError = a.describe(e));
      });
    }
  }

  void scheduleDraft() {
    draftTimer?.cancel();
    draftTimer = Timer(const Duration(milliseconds: 500), persistDraft);
  }

  Future<void> pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
      allowMultiple: true,
      withData: false,
    );
    if (result == null) return;
    require(
      selected.length + result.files.length <= 10,
      'Choose up to 10 photos for one post',
    );
    for (final f in result.files) {
      if (f.path == null) continue;
      require(f.size <= maxImageBytes, 'Each photo must be at most 20 MB');
      final destination = File('${a.directory.path}/draft-${randomId()}');
      await File(f.path!).copy(destination.path);
      selected.add(destination.path);
    }
    await saveDraft();
  }

  Widget composer() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'A new moment.',
        'The everyday is worth sharing.',
        trailing: const Icon(Icons.auto_awesome_outlined, color: accent),
      ),
      if (a.spaceId == null)
        EmptyMoment(
          icon: Icons.people_outline,
          title: 'First, find your circle.',
          message: 'Create or join a nearby space before sharing a post.',
          action: 'Find a space',
          onAction: () => navigate(5),
        )
      else ...[
        Row(
          children: [
            PersonAvatar(a.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Sharing with ${a.spaceTitle}',
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (selected.isEmpty)
          InkWell(
            onTap: a.busy ? null : () => action(pickImages),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                color: const Color(0xfffaf3f1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xfff0e1dd)),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 43,
                    color: accent,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Make it a photo moment',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Choose up to 10 photos · JPG or PNG',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: selected.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => SizedBox(
                width: 210,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        File(selected[i]),
                        fit: BoxFit.cover,
                        cacheWidth: 500,
                        errorBuilder: (_, __, ___) =>
                            const Center(child: Text('Photo unavailable')),
                      ),
                    ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: IconButton.filled(
                        tooltip: 'Remove photo ${i + 1}',
                        onPressed: a.busy
                            ? null
                            : () {
                                setState(() => selected.removeAt(i));
                                persistDraft();
                              },
                        icon: const Icon(Icons.close, size: 17),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (selected.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: a.busy || selected.length >= 10
                  ? null
                  : () => action(pickImages),
              icon: const Icon(Icons.add, size: 18),
              label: Text('Add photos · ${selected.length}/10'),
            ),
          ),
        const SizedBox(height: 20),
        TextField(
          controller: caption,
          minLines: 4,
          maxLines: 10,
          maxLength: 4000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Write a caption…\nA thought, a story, a little hello.',
          ),
          onChanged: (_) => scheduleDraft(),
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 8),
          TextField(
            controller: alt,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Describe your photos',
              helperText: 'Help everyone enjoy your moment.',
            ),
            onChanged: (_) => scheduleDraft(),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: a.busy
                    ? null
                    : () => action(
                        saveDraft,
                        success: 'Draft saved on this device',
                      ),
                child: const Text('Save draft'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: button(
                a.online ? 'Share post' : 'Queue post',
                Icons.arrow_forward_rounded,
                () async {
                  require(
                    caption.text.trim().isNotEmpty || selected.isNotEmpty,
                    'Add a caption or a photo',
                  );
                  draftTimer?.cancel();
                  await draftWrites;
                  await a.publish(
                    caption.text.trim(),
                    List.of(selected),
                    alt.text.trim(),
                  );
                  caption.clear();
                  alt.clear();
                  selected.clear();
                  loadedDraft = false;
                  await navigate(0);
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          a.pending.any(
                                (r) =>
                                    jsonDecode(r['body'] as String)['op'] ==
                                    'post.create',
                              )
                              ? 'Post saved to Activity. It will appear after the host accepts it.'
                              : 'Your moment is shared.',
                        ),
                      ),
                    );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          a.online
              ? 'Shared only with this space. Members receive their own copies.'
              : 'You’re offline. Your post will wait safely here until you reconnect.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 12),
        ),
      ],
    ],
  );
  String activityLabel(Json e) => switch (e['op']) {
    'post.create' => 'shared a new moment',
    'post.edit' => 'updated a caption',
    'post.delete' => 'removed a post',
    'post.moderate' => 'removed a post from the space',
    'comment.create' => 'added a comment',
    'comment.delete' => 'removed a comment',
    'reaction.set' =>
      e['payload']['liked'] == true ? 'liked a post' : 'removed a like',
    'profile.set' => 'updated their profile',
    'member.remove' => 'updated space membership',
    _ => 'updated the space',
  };
  Widget activity() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading('In the loop.', 'Little interactions. Real connections.'),
      if (a.pending.isNotEmpty) ...[
        const Text(
          'WAITING TO SYNC',
          style: TextStyle(
            color: muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        for (final item in a.pending)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: item['error'] == null ? canvas : const Color(0xfffff1f3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Icon(
                item['error'] == null
                    ? Icons.schedule_rounded
                    : Icons.error_outline,
                color: accent,
              ),
              title: Text(
                'You ${activityLabel(jsonDecode(item['body'] as String))}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                item['error'] ?? 'Saved on this device · waiting for your host',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () => showPending(item),
              trailing: IconButton(
                tooltip: 'Retry action',
                onPressed: a.busy
                    ? null
                    : () => action(() => a.retry(item['id'])),
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ),
          ),
        const SizedBox(height: 24),
      ],
      const Text(
        'IN YOUR SPACE',
        style: TextStyle(
          color: muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(height: 14),
      if (a.recentActivity.isEmpty)
        const EmptyMoment(
          icon: Icons.favorite_border_rounded,
          title: 'A little quiet, for now.',
          message:
              'Likes, comments, and new moments\nfrom your space will show up here.',
        ),
      for (final item in a.recentActivity)
        Builder(
          builder: (_) {
            final event = item['data'] as Json;
            final postId = event['payload']['post'] ?? event['entity'];
            final post = a.explorePosts
                .where((p) => p['id'] == postId)
                .firstOrNull;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              leading: PersonAvatar(a.nameFor(item['actor']), size: 42),
              title: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${a.nameFor(item['actor'])} ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: activityLabel(event)),
                  ],
                ),
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: event['op'] == 'comment.create'
                  ? Text(
                      event['payload']['text'] ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 12),
                    )
                  : null,
              trailing: post == null
                  ? null
                  : const Icon(Icons.chevron_right, color: muted),
              onTap: post == null ? null : () => showPost(post),
            );
          },
        ),
    ],
  );
  Future<void> showPending(Json item) async {
    final event = jsonDecode(item['body'] as String);
    final payload = event['payload'];
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your saved action'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['error'] ??
                    'This action is saved and will sync when your host is reachable.',
              ),
              if (payload['text'] != null) ...[
                const SizedBox(height: 16),
                SelectableText(payload['text']),
              ],
              if (payload['localFiles'] != null)
                Text(
                  '${(payload['localFiles'] as List).length} attached photos',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget discover() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      panel(
        'Start something nearby',
        'Choose the local interface your members can reach. Mobile hosting ends when the app is suspended.',
        [
          TextField(
            controller: spaceName,
            decoration: const InputDecoration(labelText: 'Space name'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<InternetAddress>(
            isExpanded: true,
            initialValue: address,
            items: addresses
                .map(
                  (ip) => DropdownMenuItem(
                    value: ip,
                    child: Text(
                      '${ip.address}${ip.isLoopback ? ' · this device only' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => address = v),
            decoration: const InputDecoration(
              labelText: 'Host network interface',
            ),
          ),
          const SizedBox(height: 16),
          button('Create nearby space', Icons.add_circle_outline, () async {
            require(address != null, 'No local interface available');
            draftTimer?.cancel();
            if (loadedDraft && a.spaceId != null) await saveDraft();
            await a.createSpace(spaceName.text, address!);
            loadedDraft = false;
          }),
        ],
      ),
      panel(
        'Join a space',
        'Paste the invitation received directly from your host. Compare its fingerprint with the host out of band before joining.',
        [
          TextField(
            controller: joinText,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Invitation JSON'),
          ),
          const SizedBox(height: 12),
          button('Verify & join', Icons.login, () async {
            final invite = Invitation.parse(joinText.text);
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Verify your host'),
                content: SelectableText(
                  'Endpoint: ${invite.endpoint}\n\nSHA-256 fingerprint:\n${invite.pin}\n\nCompare this with the fingerprint shown on the host device. Discovery alone does not establish trust.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Fingerprints match'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              draftTimer?.cancel();
              if (loadedDraft && a.spaceId != null) await saveDraft();
              await a.join(invite, a.name);
              loadedDraft = false;
              await navigate(0);
            }
          }),
        ],
      ),
      panel('On this network', discoveryStatus, [
        button('Scan for 5 seconds', Icons.radar, () async {
          found.clear();
          await subscription?.cancel();
          await discovery?.stop();
          discovery = NativeDiscovery();
          subscription = discovery!.discover().listen(
            (uri) {
              if (mounted) setState(() => found.add(uri));
            },
            onError: (_) {
              if (mounted)
                setState(
                  () => discoveryStatus =
                      'Discovery unavailable. Check local-network permission or use an invitation.',
                );
            },
          );
          await Future<void>.delayed(const Duration(seconds: 5));
          await discovery!.stop();
          if (mounted)
            setState(
              () => discoveryStatus = found.isEmpty
                  ? 'No advertisements found. Multicast may be blocked; a manual invitation may still work.'
                  : 'Ask the host for an invitation. Advertised endpoints are unverified.',
            );
        }),
        for (final endpoint in found)
          ListTile(
            leading: const Icon(Icons.computer),
            title: SelectableText('$endpoint'),
            subtitle: const Text('Unverified · invitation required'),
          ),
      ]),
      if (a.invitation != null && a.host != null)
        panel(
          'Invite your circle',
          'Valid for one hour, up to 10 new members. Share privately; recipients receive copies of shared content.',
          [
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(data: a.invitation!.encode(), size: 250),
              ),
            ),
            SelectableText('Host fingerprint: ${a.invitation!.pin}'),
            const SizedBox(height: 12),
            button('Copy invitation', Icons.copy, () async {
              await Clipboard.setData(
                ClipboardData(text: a.invitation!.encode()),
              );
            }),
            TextButton(
              onPressed: () => a.run(() async {
                await a.client!.request(
                  'POST',
                  '/spaces/${a.spaceId}/invite/revoke',
                  {},
                );
                a.status =
                    'Invitations revoked. Existing members retain access.';
              }),
              child: const Text('Revoke invitations'),
            ),
          ],
        ),
      if (a.spaceId != null)
        panel(
          'Members',
          'Online means a heartbeat in the last 15 seconds; it is not proof of location.',
          [
            for (final m in a.visibleMembers)
              ListTile(
                title: Text(a.nameFor(m['actor'])),
                subtitle: Text(
                  now - (m['seen'] as int) < 15000 ? 'Online now' : 'Away',
                ),
                trailing: a.host != null && m['actor'] != a.identity.id
                    ? IconButton(
                        tooltip: 'Remove member',
                        icon: const Icon(Icons.person_remove_outlined),
                        onPressed: () => a.run(
                          () => a.enqueue('member.remove', m['actor'], {}),
                        ),
                      )
                    : null,
              ),
            button(
              'Disconnect · keep cached posts',
              Icons.link_off,
              a.disconnect,
            ),
            TextButton(
              onPressed: () => a.run(a.leave),
              child: const Text('Leave space'),
            ),
          ],
        ),
    ],
  );
  Widget settings() => panel(
    a.name.isEmpty ? 'Hello, neighbor.' : 'Edit your profile',
    'No phone number, email or cloud account. This profile belongs to this device.',
    [
      TextField(
        controller: displayName,
        maxLength: 60,
        decoration: const InputDecoration(labelText: 'Display name'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: bio,
        maxLength: 300,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'A little about you'),
      ),
      const SizedBox(height: 12),
      button('Save profile', Icons.person_outline, () async {
        await a.profile(displayName.text, bio.text);
      }),
      const SizedBox(height: 24),
      SelectableText('Device fingerprint\n${a.identity.id}'),
      const SizedBox(height: 16),
      const Text(
        'Nearby sharing delivers copies to other devices. Removing a member stops future access; it cannot erase copies, exports or screenshots. The host can read space content. There is no cloud moderation team or automatic account recovery.',
      ),
      const SizedBox(height: 16),
      button(
        'Clear downloaded originals',
        Icons.cleaning_services_outlined,
        a.clearCache,
      ),
      TextButton(
        onPressed: () => a.run(() async {
          final bytes = Uint8List.fromList(utf8.encode(await a.exportData()));
          final path = await FilePicker.platform.saveFile(
            dialogTitle: 'Export local content',
            fileName: 'nearloop-local-export.json',
            bytes: bytes,
          );
          if (path != null && (Platform.isWindows || Platform.isMacOS))
            await File(path).writeAsBytes(bytes, flush: true);
        }),
        child: const Text('Export local data (without private keys)'),
      ),
      TextButton(
        onPressed: () => a.run(() async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete this device’s NearLoop data?'),
              content: const Text(
                'This permanently removes your local identity, hosted spaces, originals, cache, pending actions and drafts. There is no account recovery. Copies on other devices remain.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete local data'),
                ),
              ],
            ),
          );
          if (confirm == true) {
            await a.deleteLocalData();
            displayName.clear();
            bio.clear();
            caption.clear();
            alt.clear();
            selected.clear();
            loadedDraft = false;
          }
        }),
        child: const Text('Delete local data'),
      ),
      const SizedBox(height: 16),
      TextButton(
        onPressed: () => showLicensePage(
          context: context,
          applicationName: 'NearLoop',
          applicationVersion: '0.1.0-dev',
        ),
        child: const Text('Open-source licenses'),
      ),
    ],
  );
}
