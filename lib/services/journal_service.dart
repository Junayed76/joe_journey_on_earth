import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class JournalService {
  static final supabase = Supabase.instance.client;
  static const String ollamaUrl = 'http://10.0.2.2:11434/api/chat';

  static Future<bool> hasMessagesForDate(String userId, String date) async {
    final data = await supabase
        .from('messages')
        .select('id')
        .eq('user_id', userId)
        .gte('created_at', '${date}T00:00:00')
        .lt('created_at', '${date}T23:59:59')
        .limit(1);
    return data.isNotEmpty;
  }

  static Future<int> countFactsForDate(String userId, String date) async {
    final data = await supabase
        .from('daily_facts')
        .select('id')
        .eq('user_id', userId)
        .eq('entry_date', date);
    return data.length;
  }

  /// একটা নির্দিষ্ট date-এর জন্য শুধু category+note extract করে save করে (কোনো narrative/summary নেই)
  static Future<void> extractFactsForDay(String userId, String date) async {
    final messagesData = await supabase
        .from('messages')
        .select('sender, content')
        .eq('user_id', userId)
        .gte('created_at', '${date}T00:00:00')
        .lt('created_at', '${date}T23:59:59')
        .order('created_at');

    final messages = List<Map<String, dynamic>>.from(messagesData);
    if (messages.isEmpty) {
      print('No messages found for $date — skipping extraction.');
      return;
    }

    final conversationText = messages
        .map((m) => "${m['sender'] == 'user' ? 'User' : 'Friend'}: ${m['content']}")
        .join('\n');

    http.Response? response;
    try {
      response = await http.post(
        Uri.parse(ollamaUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'llama3.2',
          'options': {'temperature': 0.1},
          'messages': [
            {
              'role': 'system',
              'content':
              "You are reading a conversation between a user and their friend. "
                  "Find things the USER said about their day (activities, feelings, events, numbers, plans).\n"
                  "Only use lines that start with 'User:'. NEVER use anything from 'Friend:' lines, even in parentheses.\n\n"
                  "For the 'note' field:\n"
                  "- Write ONLY the final clean value. Never include meta-words like 'update to', 'changed to', 'correction', or the old value.\n"
                  "- Example: if user says 'my car is Lamborgini, I meant Lamborghini' -> note should be just 'Lamborghini', nothing else.\n"
                  "- Never include questions, even if the user asked one back.\n\n"
                  "If the same topic is mentioned more than once, merge into ONE final entry with only the latest correct value.\n"
                  "If truly nothing about their day was mentioned (only greetings like 'hi', 'ok', 'thanks'), return [].\n\n"
                  "IMPORTANT: Do not copy any numbers or examples from these instructions into your answer — only use what the user actually said in the conversation below.\n\n"
                  "Respond with ONLY the raw JSON array: [{\"category\": \"snake_case_name\", \"note\": \"clean final value\"}]. No markdown, no explanation."
            },
            {'role': 'user', 'content': conversationText},
          ],
          'stream': false,
        }),
      );

      print('OLLAMA STATUS for $date: ${response.statusCode}');

      final data = jsonDecode(response.body);
      String raw = (data['message']['content'] ?? '[]').toString();
      raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();

      print('PARSED FACTS RAW for $date: $raw');

      final List<dynamic> facts = jsonDecode(raw);

      await supabase.from('daily_facts').delete().eq('user_id', userId).eq('entry_date', date);

      if (facts.isNotEmpty) {
        final rows = facts
            .where((f) => f['category'] != null && f['note'] != null)
            .map((f) => {
          'user_id': userId,
          'entry_date': date,
          'category': f['category'],
          'note': f['note'],
        })
            .toList();
        if (rows.isNotEmpty) {
          final inserted = await supabase.from('daily_facts').insert(rows).select();
          print('INSERTED ${inserted.length} facts for $date');
        } else {
          print('No valid rows to insert for $date (facts had null category/note)');
        }
      } else {
        print('Ollama returned empty facts array for $date');
      }
    } catch (e) {
      print('EXTRACT FACTS ERROR for $date: $e');
      if (response != null) {
        print('RAW OLLAMA RESPONSE BODY: ${response.body}');
      }
    }
  }

  /// Journal button চাপলে call হবে — গত ৩০ দিনের মধ্যে যেসব দিনে message আছে কিন্তু facts নেই, সেগুলো extract করে,
  /// আর আজকের দিনটা সবসময় re-check করে (নতুন message এসে থাকতে পারে)
  static Future<void> syncAll(String userId) async {
    final today = DateTime.now();
    print('SYNC START for user $userId');

    for (int i = 0; i <= 7; i++) {
      final date = today.subtract(Duration(days: i));
      final dateStr = date.toIso8601String().split('T')[0];

      final hasMsgs = await hasMessagesForDate(userId, dateStr);
      print('Checking $dateStr — hasMessages: $hasMsgs');
      if (!hasMsgs) continue;

      if (i == 0) {
        print('Extracting for today: $dateStr');
        await extractFactsForDay(userId, dateStr);
      } else {
        final factCount = await countFactsForDate(userId, dateStr);
        print('$dateStr — existing fact count: $factCount');
        if (factCount == 0) {
          print('Extracting for $dateStr');
          await extractFactsForDay(userId, dateStr);
        }
      }
    }
    print('SYNC DONE');
  }
  }
