import 'dart:convert';
import 'package:flutter/material.dart';
import '../../features/settings/settings_screen.dart';
import '../../services/journal_writer_service.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/journal_service.dart';
import '../../theme/app_theme.dart';
import '../Insight/insight_screen.dart';
import '../journals/journal_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _messages = [];
  List<String> _quickReplies = [];
  bool _loading = true;

  static const String ollamaUrl = 'http://10.0.2.2:11434/api/chat';
  static const String systemPrompt =
      "You are JOE, a warm, casual friend chatting with the user in the evening. Ask about their day naturally, like a close friend catching up — not like an assistant. Keep replies short (1-3 sentences), conversational, and curious. Never sound robotic or use bullet points.";
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels <= 50) _loadOlderMessages();
    });
    _loadMessages().then((_) => _maybeStartConversation());
  }

  static const int _pageSize = 30;
  bool _hasMore = true;
  bool _loadingMore = false;

  Future<void> _loadMessages() async {
    final userId = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('messages')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(_pageSize);

    final list = List<Map<String, dynamic>>.from(data).reversed.toList();

    setState(() {
      _messages = list;
      _loading = false;
      _hasMore = list.length == _pageSize;
    });

    await Future.delayed(const Duration(milliseconds: 100));
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Future<void> _loadOlderMessages() async {
    if (!_hasMore || _loadingMore || _messages.isEmpty) return;
    setState(() => _loadingMore = true);

    final userId = supabase.auth.currentUser!.id;
    final oldest = _messages.first['created_at'];
    final data = await supabase
        .from('messages')
        .select()
        .eq('user_id', userId)
        .lt('created_at', oldest)
        .order('created_at', ascending: false)
        .limit(_pageSize);

    final older = List<Map<String, dynamic>>.from(data).reversed.toList();
    setState(() {
      _messages = [...older, ..._messages];
      _hasMore = older.length == _pageSize;
      _loadingMore = false;
    });
  }

  Future<void> _deleteMessage(String id) async {
    await supabase.from('messages').delete().eq('id', id);
    setState(() => _messages.removeWhere((m) => m['id'] == id));
  }

  Future<void> _maybeStartConversation() async {
    final userId = supabase.auth.currentUser!.id;
    final today = DateTime.now().toIso8601String().split('T')[0];

    final todayAiMessages = await supabase
        .from('messages')
        .select('id')
        .eq('user_id', userId)
        .eq('sender', 'ai')
        .gte('created_at', '${today}T00:00:00');

    if (todayAiMessages.isNotEmpty) return;

    final pastEntries = await supabase
        .from('daily_facts')
        .select('entry_date, category, note')
        .eq('user_id', userId)
        .order('entry_date', ascending: false)
        .limit(15);

    String memoryContext =
        "This is the first time you're talking to this user, you don't know anything about them yet.";
    if (pastEntries.isNotEmpty) {
      final entries = List<Map<String, dynamic>>.from(pastEntries);
      memoryContext = "Here are some facts about the user's recent days:\n" +
          entries.map((e) => "${e['entry_date']} - ${e['category']}: ${e['note']}").join('\n');
    }

    setState(() => _loading = true);

    try {
      final response = await http.post(
        Uri.parse(ollamaUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'llama3.2',
          'messages': [
            {
              'role': 'system',
              'content':
              "$systemPrompt $memoryContext\n\nStart a short, casual, warm conversation opener (1-2 sentences) asking about their day. If you know something specific from a recent day, naturally reference it — like a friend who remembers."
            },
            {'role': 'user', 'content': 'Start the conversation.'},
          ],
          'stream': false,
        }),
      );

      final data = jsonDecode(response.body);
      final opener = data['message']['content'] ?? "Hey! How was your day today?";

      await supabase.from('messages').insert({
        'user_id': userId,
        'sender': 'ai',
        'content': opener,
      });

      await _loadMessages();
      await _generateQuickReplies(opener);
    } catch (e) {
      debugPrint('CONVERSATION START ERROR: $e');
    }

    setState(() => _loading = false);
  }

  Future<void> _generateQuickReplies(String lastAiMessage) async {
    try {
      final response = await http.post(
        Uri.parse(ollamaUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'llama3.2',
          'messages': [
            {
              'role': 'system',
              'content':
              "You decide whether a chat message needs short quick-reply suggestions. "
                  "ONLY generate quick replies if the friend's message is a simple, closed-style question that naturally invites a short answer. "
                  "DO NOT generate quick replies if the message is open-ended and expects the user to explain or share details. "
                  "If appropriate, respond ONLY with a raw JSON array of exactly 3 short first-person options (each under 6 words). "
                  "If NOT appropriate, respond ONLY with an empty JSON array: []. "
                  "No markdown, no explanation."
            },
            {'role': 'user', 'content': 'Friend said: "$lastAiMessage". Decide and respond with the JSON array.'},
          ],
          'stream': false,
        }),
      );

      final data = jsonDecode(response.body);
      String raw = (data['message']['content'] ?? '[]').toString();
      raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final List<dynamic> parsed = jsonDecode(raw);
      setState(() => _quickReplies = parsed.map((e) => e.toString()).toList());
    } catch (e) {
      debugPrint('QUICK REPLY ERROR: $e');
      setState(() => _quickReplies = []);
    }
  }

  // ================= Message classification =================
  // তিনটা ধরনের message আলাদা করে: normal chat, data-read query, data-write command (CRUD)
  Future<Map<String, dynamic>> _classifyMessage(String text) async {
    try {
      final response = await http.post(
        Uri.parse(ollamaUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'llama3.2',
          'options': {'temperature': 0.1},
          'messages': [
            {
              'role': 'system',
              'content':
              "Classify the user's message into exactly ONE of these types:\n"
                  "- \"chat\": normal conversation about their day, feelings, etc.\n"
                  "- \"read\": a question asking about their OWN past stored data (e.g. 'how much did I study', 'what's my mood history').\n"
                  "- \"write\": an explicit command to CREATE, UPDATE, or DELETE their stored data (e.g. 'delete my study entry', 'change gaming to 3 hours', 'remove today's mood data', 'add a note that I exercised').\n"
                  "- \"goal\": user is setting a personal target (e.g. 'I want to read 15 books this year', 'goal: study 100 hours this month', 'I want to travel to 5 places this year').\n\n"
                  "Respond ONLY with raw JSON: {\"type\": \"chat_or_read_or_write_or_goal\", \"action\": \"create_or_update_or_delete_or_null\", \"category\": \"snake_case_category_or_null\", \"note\": \"new_note_value_or_null\", \"days\": number_to_look_back_for_read_or_null, \"goal_category\": \"snake_case_category_or_null\", \"goal_target\": number_or_null, \"goal_unit\": \"hours_or_count_or_null\", \"goal_period\": \"week_or_month_or_year_or_null\"}. "
                  "For write commands, extract the category and the new note value. Default entry_date is today unless the user specifies otherwise. "
                  "For goal commands, extract goal_category (e.g. 'books', 'study', 'travel'), goal_target (the number), goal_unit ('count' for things like books/places, 'hours' for time-based goals), and goal_period ('week', 'month', or 'year' based on what the user said). "
                  "No markdown, no explanation — just the raw JSON object."},
            {'role': 'user', 'content': text},
          ],
          'stream': false,
        }),
      );

      final data = jsonDecode(response.body);
      String raw = (data['message']['content'] ?? '{}').toString();
      raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (e) {
      debugPrint('CLASSIFY ERROR: $e');
      return {'type': 'chat'};
    }
  }

  // ================= READ: শুধু database থেকে real data দিয়ে answer বানায় =================
  Future<String> _answerDataQuery(String question, int days) async {
    final userId = supabase.auth.currentUser!.id;
    final since = DateTime.now().subtract(Duration(days: days)).toIso8601String().split('T')[0];

    final facts = await supabase
        .from('daily_facts')
        .select('entry_date, category, note')
        .eq('user_id', userId)
        .gte('entry_date', since)
        .order('entry_date');

    final factsList = List<Map<String, dynamic>>.from(facts);

    if (factsList.isEmpty) {
      return "এই সময়ের মধ্যে তেমন কোনো data পাইনি এখনো — আরও কিছুদিন chat করলে answer দিতে পারবো।";
    }

    final contextData = factsList.map((f) => "${f['entry_date']} - ${f['category']}: ${f['note']}").join('\n');

    final response = await http.post(
      Uri.parse(ollamaUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': 'llama3.2',
        'options': {'temperature': 0.2},
        'messages': [
          {
            'role': 'system',
            'content':
            "You are JOE, the user's friend who has access to their personal stored data. Answer their question using ONLY the data provided below — never invent facts. "
                "Keep it conversational and warm.\n\nStored data:\n$contextData"
          },
          {'role': 'user', 'content': question},
        ],
        'stream': false,
      }),
    );

    final data = jsonDecode(response.body);
    return data['message']['content'] ?? "দুঃখিত, answer বের করতে পারলাম না।";
  }

  // ================= WRITE: user command অনুযায়ী সরাসরি table-এ CRUD =================
  Future<String> _executeDataCommand(Map<String, dynamic> classification) async {
    final userId = supabase.auth.currentUser!.id;
    final today = DateTime.now().toIso8601String().split('T')[0];
    final action = classification['action'];
    final category = classification['category'];
    final note = classification['note'];

    if (category == null) {
      return "কোন category নিয়ে বলছো ঠিক বুঝতে পারলাম না, আরেকটু স্পষ্ট করে বলো?";
    }

    switch (action) {
      case 'delete':
        await supabase
            .from('daily_facts')
            .delete()
            .eq('user_id', userId)
            .eq('entry_date', today)
            .eq('category', category);
        return "ঠিক আছে, আজকের '$category' data মুছে দিলাম।";

      case 'update':
        final existing = await supabase
            .from('daily_facts')
            .select('id')
            .eq('user_id', userId)
            .eq('entry_date', today)
            .eq('category', category)
            .maybeSingle();

        if (existing != null) {
          await supabase.from('daily_facts').update({'note': note}).eq('id', existing['id']);
        } else {
          await supabase.from('daily_facts').insert({
            'user_id': userId,
            'entry_date': today,
            'category': category,
            'note': note,
          });
        }
        return "আপডেট হয়ে গেছে — '$category': $note।";

      case 'create':
      default:
        await supabase.from('daily_facts').insert({
          'user_id': userId,
          'entry_date': today,
          'category': category,
          'note': note ?? '',
        });
        return "যোগ করে দিলাম — '$category': ${note ?? ''}।";
    }
  }

  Future<void> _sendMessage([String? overrideText]) async {
    final text = overrideText ?? _controller.text.trim();
    if (text.isEmpty) return;
    final userId = supabase.auth.currentUser!.id;

    _controller.clear();
    setState(() => _quickReplies = []);

    await supabase.from('messages').insert({
      'user_id': userId,
      'sender': 'user',
      'content': text,
    });

    await _loadMessages();
    setState(() => _loading = true);

    try {
      final classification = await _classifyMessage(text);
      String aiReply;
      bool wasChat = false;

      switch (classification['type']) {
        case 'read':
          aiReply = await _answerDataQuery(text, classification['days'] ?? 30);
          break;
        case 'goal':
          await JournalWriterService.setGoal(
            userId,
            classification['goal_category'] ?? 'goal',
            classification['goal_target'] ?? 0,
            classification['goal_unit'] ?? 'count',
            classification['goal_period'] ?? 'month',
          );
          aiReply = "লক্ষ্য set করা হলো — ${classification['goal_target']} ${classification['goal_unit']} ${classification['goal_category']}, এই ${classification['goal_period']}-এ।";
          break;
        case 'write':
          aiReply = await _executeDataCommand(classification);
          break;
        case 'chat':
        default:
          wasChat = true;
          final ollamaMessages = [
            {'role': 'system', 'content': systemPrompt},
            ..._messages.map((m) => {
              'role': m['sender'] == 'user' ? 'user' : 'assistant',
              'content': m['content'],
            }),
          ];
          final response = await http.post(
            Uri.parse(ollamaUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'model': 'llama3.2', 'messages': ollamaMessages, 'stream': false}),
          );
          final data = jsonDecode(response.body);
          aiReply = data['message']['content'] ?? "Sorry, no reply.";
      }

      await supabase.from('messages').insert({
        'user_id': userId,
        'sender': 'ai',
        'content': aiReply,
      });

      await _loadMessages();
      if (wasChat) {
        await _generateQuickReplies(aiReply);
      }
    } catch (e) {
      debugPrint('SEND MESSAGE ERROR: $e');
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _messages.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('JOE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['sender'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser ? AppColors.terracotta : AppColors.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isUser ? 18 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 18),
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 5, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Text(
                      msg['content'],
                      style: TextStyle(
                        color: isUser ? AppColors.appBarBg : AppColors.textDark,
                        fontSize: 14.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_quickReplies.isNotEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _quickReplies.map((reply) {
                  return ActionChip(
                    label: Text(reply),
                    backgroundColor: AppColors.terracottaSoft,
                    side: BorderSide.none,
                    labelStyle: TextStyle(color: AppColors.textDark, fontSize: 13),
                    onPressed: () => _sendMessage(reply),
                  );
                }).toList(),
              ),
            ),
          if (_loading && _messages.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.terracottaSoft, width: 1),
                    ),
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(fontSize: 14.5),
                      decoration: InputDecoration(
                        hintText: 'কিছু লিখো...',
                        hintStyle: TextStyle(color: AppColors.textMuted),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(color: AppColors.terracotta, shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: () => _sendMessage(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}