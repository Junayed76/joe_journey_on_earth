import 'package:supabase_flutter/supabase_flutter.dart';

class StoryService {
  static final supabase = Supabase.instance.client;

  static String authorLabel() {
    final user = supabase.auth.currentUser;
    if (user?.email != null && user!.email!.isNotEmpty) {
      return user.email!.split('@')[0];
    }
    return 'Anonymous';
  }

  static Future<List<Map<String, dynamic>>> fetchFeed({String? query}) async {
    var builder = supabase
        .from('stories')
        .select('id, author_label, content, source_date, created_at');

    if (query != null && query.trim().isNotEmpty) {
      builder = builder.ilike('content', '%${query.trim()}%');
    }

    final data = await builder.order('created_at', ascending: false).limit(50);
    final stories = List<Map<String, dynamic>>.from(data);
    if (stories.isEmpty) return [];

    final ids = stories.map((s) => s['id'].toString()).toList();
    final likes = await supabase.from('story_likes').select('story_id, user_id').inFilter('story_id', ids);
    final comments = await supabase.from('story_comments').select('story_id').inFilter('story_id', ids);

    final userId = supabase.auth.currentUser!.id;
    final likesList = List<Map<String, dynamic>>.from(likes);
    final commentsList = List<Map<String, dynamic>>.from(comments);

    for (final s in stories) {
      final sid = s['id'].toString();
      s['like_count'] = likesList.where((l) => l['story_id'] == sid).length;
      s['comment_count'] = commentsList.where((c) => c['story_id'] == sid).length;
      s['liked_by_me'] = likesList.any((l) => l['story_id'] == sid && l['user_id'] == userId);
    }
    return stories;
  }
  static Future<void> publish(String content, {String? sourceDate}) async {
    final userId = supabase.auth.currentUser!.id;
    await supabase.from('stories').insert({
      'user_id': userId,
      'author_label': authorLabel(),
      'content': content,
      'source_date': sourceDate,
    });
  }

  static Future<List<Map<String, dynamic>>> fetchMyJournals() async {
    final userId = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('journal_entries')
        .select('entry_date, content')
        .eq('user_id', userId)
        .eq('period_type', 'day')
        .eq('is_placeholder', false)
        .order('entry_date', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  static Future<void> toggleLike(String storyId, bool currentlyLiked) async {
    final userId = supabase.auth.currentUser!.id;
    if (currentlyLiked) {
      await supabase.from('story_likes').delete().eq('story_id', storyId).eq('user_id', userId);
    } else {
      await supabase.from('story_likes').insert({'story_id': storyId, 'user_id': userId});
    }
  }

  static Future<List<Map<String, dynamic>>> fetchComments(String storyId) async {
    final data = await supabase
        .from('story_comments')
        .select('author_label, content, created_at')
        .eq('story_id', storyId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  static Future<void> addComment(String storyId, String content) async {
    final userId = supabase.auth.currentUser!.id;
    await supabase.from('story_comments').insert({
      'story_id': storyId,
      'user_id': userId,
      'author_label': authorLabel(),
      'content': content,
    });
  }
}