import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:protocol/protocol.dart';
import 'package:transport/transport.dart';
import 'controller.dart';

const ink = Color(0xff202127);
const muted = Color(0xff777982);
const accent = Color(0xffdd3564);
const line = Color(0xffededf0);
const canvas = Color(0xfffafafa);

class PersonAvatar extends StatelessWidget {
  final String name;
  final double size;
  final bool ring;
  const PersonAvatar(this.name, {super.key, this.size = 40, this.ring = false});
  @override
  Widget build(BuildContext context) {
    final label = name.trim().isEmpty
        ? 'N'
        : name.trim().characters.first.toUpperCase();
    final colors = [
      const Color(0xfff9e5de),
      const Color(0xffe2eaf2),
      const Color(0xffe7e5f2),
      const Color(0xffe0eee8),
    ];
    final hash = name.codeUnits.fold<int>(0, (a, b) => a + b);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring ? 3 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: ring
            ? const LinearGradient(
                colors: [Color(0xffffbc77), accent, Color(0xff984cbb)],
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
              )
            : null,
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors[hash % colors.length],
          border: ring ? Border.all(color: Colors.white, width: 3) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: size * .36,
            color: ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class EmptyMoment extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final String? action;
  final VoidCallback? onAction;
  const EmptyMoment({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 52),
    child: Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: const BoxDecoration(
            color: Color(0xfff8e9ed),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 35, color: accent),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -.7,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, height: 1.6),
        ),
        if (action != null) ...[
          const SizedBox(height: 24),
          FilledButton(onPressed: onAction, child: Text(action!)),
        ],
      ],
    ),
  );
}

class MediaTile extends StatefulWidget {
  final AppController app;
  final String hash, alt;
  final bool compact;
  const MediaTile(
    this.app,
    this.hash,
    this.alt, {
    super.key,
    this.compact = false,
  });
  @override
  State<MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<MediaTile> {
  String? path, error;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    _cached();
  }

  @override
  void didUpdateWidget(MediaTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hash != widget.hash) {
      path = null;
      error = null;
      _cached();
    }
  }

  Future<void> _cached() async {
    final hash = widget.hash;
    for (final folder in ['cache', 'media']) {
      final file = File(
        '${widget.app.directory.path}/$folder/${widget.app.spaceId}-$hash',
      );
      if (await file.exists() && mounted && hash == widget.hash) {
        setState(() => path = file.path);
        return;
      }
    }
  }

  Future<void> download() async {
    if (widget.app.client == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await FileTransfers(
        widget.app.client!,
        Directory('${widget.app.directory.path}/cache'),
      ).download(widget.hash);
      if (mounted) setState(() => path = result);
    } catch (e) {
      if (mounted) setState(() => error = widget.app.describe(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (path != null)
      return Image.file(
        File(path!),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        cacheWidth: widget.compact ? 420 : 1200,
        semanticLabel: widget.alt.isEmpty ? 'Shared photo' : widget.alt,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined, color: muted),
        ),
      );
    return ColoredBox(
      color: const Color(0xfff1eeeb),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: widget.compact
              ? const Icon(Icons.image_outlined, color: muted, size: 28)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.image_outlined, size: 40, color: muted),
                    const SizedBox(height: 14),
                    Text(
                      error ??
                          (widget.app.client == null
                              ? 'Photo available when you reconnect'
                              : 'A moment worth keeping'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: muted),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: loading || widget.app.client == null
                          ? null
                          : download,
                      icon: Icon(
                        loading ? Icons.hourglass_top : Icons.download_outlined,
                      ),
                      label: Text(
                        loading ? 'Downloading…' : 'Load original photo',
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Original quality · up to 20 MB',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class PhotoCarousel extends StatefulWidget {
  final AppController app;
  final List<String> images;
  final String alt;
  final VoidCallback onLike;
  const PhotoCarousel({
    super.key,
    required this.app,
    required this.images,
    required this.alt,
    required this.onLike,
  });
  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel> {
  int index = 0;
  final pager = PageController();
  @override
  void dispose() {
    pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      AspectRatio(
        aspectRatio: 1,
        child: Stack(
          children: [
            GestureDetector(
              onDoubleTap: widget.onLike,
              child: PageView.builder(
                controller: pager,
                itemCount: widget.images.length,
                onPageChanged: (i) => setState(() => index = i),
                itemBuilder: (_, i) => MediaTile(
                  widget.app,
                  widget.images[i],
                  widget.alt,
                  key: ValueKey(widget.images[i]),
                ),
              ),
            ),
            if (widget.images.length > 1) ...[
              Positioned(
                top: 14,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${index + 1}/${widget.images.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
              if (index > 0)
                Positioned(
                  left: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton.filledTonal(
                      tooltip: 'Previous photo',
                      onPressed: () => pager.previousPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                      icon: const Icon(Icons.chevron_left),
                    ),
                  ),
                ),
              if (index < widget.images.length - 1)
                Positioned(
                  right: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton.filledTonal(
                      tooltip: 'Next photo',
                      onPressed: () => pager.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
      if (widget.images.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.images.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: i == index ? 14 : 5,
                height: 5,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: i == index ? accent : line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class CommentsSheet extends StatefulWidget {
  final AppController app;
  final Json post;
  const CommentsSheet({super.key, required this.app, required this.post});
  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final input = TextEditingController();
  final scroll = ScrollController();
  List<Json> rows = [];
  String? error;
  bool sending = false, loading = true;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    widget.app.addListener(reload);
    reload();
  }

  Future<void> reload() async {
    final current = ++generation;
    try {
      final comments = await widget.app.commentsFor(widget.post['id']);
      if (mounted && current == generation)
        setState(() {
          rows = comments;
          loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          loading = false;
          error = 'Could not load comments. Please reopen this post.';
        });
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(reload);
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final value = input.text.trim();
    if (value.isEmpty || sending) return;
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await widget.app.enqueue('comment.create', randomId(), {
        'post': widget.post['id'],
        'text': value,
      });
      input.clear();
      await reload();
      if (mounted && scroll.hasClients)
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
    } catch (e) {
      if (mounted) setState(() => error = widget.app.describe(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final queued = app.pending.where((row) {
      final e = jsonDecode(row['body'] as String);
      return e['op'] == 'comment.create' &&
          e['payload']['post'] == widget.post['id'];
    }).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Comments',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close comments',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        controller: scroll,
                        padding: const EdgeInsets.all(20),
                        children: [
                          if (rows.isEmpty && queued.isEmpty)
                            const EmptyMoment(
                              icon: Icons.chat_bubble_outline_rounded,
                              title: 'Start the conversation',
                              message:
                                  'A little kindness goes a long way.\nLeave the first comment.',
                            ),
                          for (final row in rows)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  PersonAvatar(
                                    app.nameFor(row['actor']),
                                    size: 34,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          app.nameFor(row['actor']),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          row['data']['text'],
                                          style: const TextStyle(height: 1.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (row['actor'] == app.identity.id)
                                    IconButton(
                                      tooltip: 'Delete your comment',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.close,
                                        size: 16,
                                        color: muted,
                                      ),
                                      onPressed: app.busy
                                          ? null
                                          : () => app.run(
                                              () => app.enqueue(
                                                'comment.delete',
                                                row['id'],
                                                {},
                                                revision: row['revision'],
                                              ),
                                            ),
                                    ),
                                ],
                              ),
                            ),
                          for (final row in queued)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: PersonAvatar(app.name, size: 34),
                              title: Text(
                                jsonDecode(
                                  row['body'] as String,
                                )['payload']['text'],
                              ),
                              subtitle: Text(
                                row['error'] ?? 'Waiting to sync',
                                style: TextStyle(
                                  color: row['error'] == null ? muted : accent,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(error!, style: const TextStyle(color: accent)),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    PersonAvatar(app.name, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: input,
                        minLines: 1,
                        maxLines: 3,
                        maxLength: 4000,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'Add a comment…',
                          counterText: '',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          filled: false,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: sending || input.text.trim().isEmpty
                          ? null
                          : send,
                      child: Text(sending ? 'Sending…' : 'Post'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
