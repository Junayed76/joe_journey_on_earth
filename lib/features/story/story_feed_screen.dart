import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/story_service.dart';
import '../../theme/app_theme.dart';
import 'compose_story_screen.dart';

class StoryFeedScreen extends StatefulWidget {
  const StoryFeedScreen({super.key});
  @override
  State<StoryFeedScreen> createState() => _StoryFeedScreenState();
}

class _StoryFeedScreenState extends State<StoryFeedScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _stories = [];

  bool _searchOpen = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final data = await StoryService.fetchFeed();
    if (!mounted) return;
    setState(() {
      _stories = data;
      _loading = false;
    });
  }

  Future<void> _search() async {
    if (mounted) setState(() => _loading = true);
    final data = await StoryService.fetchFeed(query: _searchController.text);
    if (!mounted) return;
    setState(() {
      _stories = data;
      _loading = false;
    });
  }

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (!_searchOpen) {
      _searchController.clear();
      _load();
    }
  }

  Future<void> _openCompose() async {
    final published = await Navigator.push(context, MaterialPageRoute(builder: (_) => const ComposeStoryScreen()));
    if (published == true) _load();
  }

  Future<void> _toggleLike(Map<String, dynamic> s) async {
    final liked = s['liked_by_me'] == true;
    setState(() {
      s['liked_by_me'] = !liked;
      s['like_count'] = (s['like_count'] as int) + (liked ? -1 : 1);
    });
    await StoryService.toggleLike(s['id'].toString(), liked);
  }

  Future<void> _shareStory(String content) async {
    try {
      await SharePlus.instance.share(ShareParams(text: content));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share করা যায়নি।')),
        );
      }
    }
  }

  void _openComments(Map<String, dynamic> s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _CommentSheet(storyId: s['id'].toString(), onCommentAdded: _load),
    );
  }

  String _relativeTime(String iso) {
    final d = DateTime.parse(iso);
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'এইমাত্র';
    if (diff.inMinutes < 60) return '${diff.inMinutes} মিনিট আগে';
    if (diff.inHours < 24) return '${diff.inHours} ঘণ্টা আগে';
    return '${diff.inDays} দিন আগে';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Story'),
        actions: [
          IconButton(
            icon: Icon(_searchOpen ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_searchOpen) ...[
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Story-তে কিছু খোঁজো...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.terracottaSoft),
                  ),
                ),
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 14),
            ] else ...[
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _openCompose,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.terracottaSoft),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.edit_note, color: AppColors.textMuted, size: 20),
                      const SizedBox(width: 10),
                      Text('Write something...', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],

            if (_stories.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    _searchOpen ? 'কোনো story পাওয়া যায়নি।' : 'এখনো কোনো story নেই। প্রথম হয়ে যাও!',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              )
            else
              ..._stories.map((s) {
                final content = s['content'].toString();
                final liked = s['liked_by_me'] == true;
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.terracottaSoft,
                            child: Text(
                              (s['author_label'] as String).isNotEmpty
                                  ? (s['author_label'] as String)[0].toUpperCase()
                                  : '?',
                              style: TextStyle(color: AppColors.terracotta, fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s['author_label'].toString(),
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                Text(_relativeTime(s['created_at'].toString()),
                                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(content, style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.textDark)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          InkWell(
                            onTap: () => _toggleLike(s),
                            child: Row(
                              children: [
                                Icon(liked ? Icons.favorite : Icons.favorite_border,
                                    size: 18, color: liked ? AppColors.blush : AppColors.textMuted),
                                const SizedBox(width: 4),
                                Text('${s['like_count']}', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          InkWell(
                            onTap: () => _openComments(s),
                            child: Row(
                              children: [
                                Icon(Icons.chat_bubble_outline, size: 17, color: AppColors.textMuted),
                                const SizedBox(width: 4),
                                Text('${s['comment_count']}', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: () => _shareStory(content),
                            child: Icon(Icons.share_outlined, size: 17, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _CommentSheet extends StatefulWidget {
  final String storyId;
  final VoidCallback onCommentAdded;
  const _CommentSheet({required this.storyId, required this.onCommentAdded});

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await StoryService.fetchComments(widget.storyId);
    if (!mounted) return;
    setState(() {
      _comments = data;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    await StoryService.addComment(widget.storyId, text);
    _controller.clear();
    await _load();
    widget.onCommentAdded();
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.65,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Comments', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _comments.isEmpty
                  ? Center(child: Text('এখনো কোনো comment নেই।', style: TextStyle(color: AppColors.textMuted)))
                  : ListView.builder(
                itemCount: _comments.length,
                itemBuilder: (context, i) {
                  final c = _comments[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c['author_label'].toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                        const SizedBox(height: 2),
                        Text(c['content'].toString(), style: const TextStyle(fontSize: 13.5, height: 1.4)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'একটা comment লেখো...',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.send, color: AppColors.terracotta),
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}