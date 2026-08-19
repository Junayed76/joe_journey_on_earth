import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class JournalWriterService {
  static final supabase = Supabase.instance.client;
  static const String ollamaUrl = 'http://10.0.2.2:11434/api/chat';

  static Future<String> _askOllama(String systemPrompt, String userContent) async {
    final response = await http.post(
      Uri.parse(ollamaUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': 'llama3.2',
        'options': {'temperature': 0.4},
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userContent},
        ],
        'stream': false,
      }),
    );
    final data = jsonDecode(response.body);
    return (data['message']['content'] ?? '').toString().trim();
  }

  static Future<bool> _exists(String userId, String date, String type) async {
    final row = await supabase
        .from('journal_entries')
        .select('id')
        .eq('user_id', userId)
        .eq('entry_date', date)
        .eq('period_type', type)
        .maybeSingle();
    return row != null;
  }

  static Future<void> _save(String userId, String date, String type, String content) async {
    if (content.isEmpty) return;
    try {
      await supabase.from('journal_entries').insert({
        'user_id': userId,
        'entry_date': date,
        'period_type': type,
        'content': content,
      });
      print('SAVED $type journal for $date');
    } catch (e) {
      print('SAVE JOURNAL ERROR ($type, $date): $e');
    }
  }

  /// একটা নির্দিষ্ট দিনের journal লেখে (শুধু আগের দিনগুলোর জন্য call হবে, আজকের জন্য না)
  static Future<void> _writeDayJournal(String userId, DateTime date) async {
    final dateStr = date.toIso8601String().split('T')[0];
    if (await _exists(userId, dateStr, 'day')) return;

    final msgs = await supabase
        .from('messages')
        .select('sender, content')
        .eq('user_id', userId)
        .gte('created_at', '${dateStr}T00:00:00')
        .lt('created_at', '${dateStr}T23:59:59')
        .order('created_at');

    final list = List<Map<String, dynamic>>.from(msgs);

    // কোনো chat না থাকলে — placeholder entry বসিয়ে দাও, যাতে feed-এ দিনটা visible থাকে
    if (list.isEmpty) {
      await _savePlaceholder(userId, dateStr);
      return;
    }

    final convo = list
        .map((m) => "${m['sender'] == 'user' ? 'User' : 'Friend'}: ${m['content']}")
        .join('\n');

    final journal = await _askOllama(
      "You are writing a personal diary entry for the user, in FIRST PERSON ('I ...'), "
          "based on their conversation with a friend below. Only include things the user actually said "
          "(lines starting with 'User:'). Write it like a warm, reflective diary entry about the day — "
          "3 to 6 sentences. Do not mention the friend or that this was a chat. Do not invent details. "
          "If there's nothing meaningful to write about, respond with exactly: NOTHING",
      convo,
    );

    if (journal.trim().toUpperCase() == 'NOTHING' || journal.isEmpty) {
      await _savePlaceholder(userId, dateStr);
      return;
    }

    await _save(userId, dateStr, 'day', journal);
    await _extractInsightFacts(userId, dateStr, convo);
  }

  static Future<void> _savePlaceholder(String userId, String dateStr) async {
    const placeholderText =
        "এই দিনের কিছু লেখা হয়নি। কী হয়েছিল মনে আছে? Tap করে নিজেই লিখে ফেলো।";
    try {
      await supabase.from('journal_entries').insert({
        'user_id': userId,
        'entry_date': dateStr,
        'period_type': 'day',
        'content': placeholderText,
        'is_placeholder': true,
      });
      print('SAVED placeholder for $dateStr');
    } catch (e) {
      print('SAVE PLACEHOLDER ERROR ($dateStr): $e');
    }
  }

  /// আগের মাসের journal লেখে, সেই মাসের day-journal গুলো জোড়া দিয়ে
  static Future<void> _writeMonthJournal(String userId, DateTime firstOfMonth) async {
    final dateStr = firstOfMonth.toIso8601String().split('T')[0];
    if (await _exists(userId, dateStr, 'month')) return;

    final nextMonth = DateTime(firstOfMonth.year, firstOfMonth.month + 1, 1);
    final dayEntries = await supabase
        .from('journal_entries')
        .select('entry_date, content')
        .eq('user_id', userId)
        .eq('period_type', 'day')
        .gte('entry_date', dateStr)
        .lt('entry_date', nextMonth.toIso8601String().split('T')[0])
        .order('entry_date');

    final list = List<Map<String, dynamic>>.from(dayEntries);
    if (list.isEmpty) return;

    final combined = list.map((e) => "${e['entry_date']}: ${e['content']}").join('\n\n');

    final journal = await _askOllama(
      "Below are daily diary entries the user wrote across a month, in first person. "
          "Write ONE reflective monthly summary entry, in FIRST PERSON, capturing the overall themes, "
          "highlights, and feelings of the month. 4 to 7 sentences. Do not list every day individually.",
      combined,
    );

    if (journal.isEmpty) return;
    await _save(userId, dateStr, 'month', journal);
  }

  /// আগের বছরের journal লেখে, সেই বছরের month-journal গুলো জোড়া দিয়ে
  static Future<void> _writeYearJournal(String userId, int year) async {
    final dateStr = "$year-01-01";
    if (await _exists(userId, dateStr, 'year')) return;

    final monthEntries = await supabase
        .from('journal_entries')
        .select('entry_date, content')
        .eq('user_id', userId)
        .eq('period_type', 'month')
        .gte('entry_date', '$year-01-01')
        .lt('entry_date', '${year + 1}-01-01')
        .order('entry_date');

    final list = List<Map<String, dynamic>>.from(monthEntries);
    if (list.isEmpty) return;

    final combined = list.map((e) => "${e['entry_date']}: ${e['content']}").join('\n\n');

    final journal = await _askOllama(
      "Below are monthly diary summaries the user wrote across a year, in first person. "
          "Write ONE reflective year-in-review entry, in FIRST PERSON, capturing the overall arc, "
          "growth, and feelings of the year. 5 to 8 sentences.",
      combined,
    );

    if (journal.isEmpty) return;
    await _save(userId, dateStr, 'year', journal);
  }

  /// Journal screen খুললে call হবে — মিসিং day/month/year journal থাকলে লিখে save করে দেয়, একবারই
  static Future<void> syncJournals(String userId) async {
    final today = DateTime.now();
    final todayStr = today.toIso8601String().split('T')[0];

    // User-এর account কবে তৈরি হয়েছে সেটা বের করো — তার আগের কোনো দিনের জন্য placeholder বানানো যাবে না
    final createdAtStr = supabase.auth.currentUser?.createdAt;
    DateTime accountStart = today;
    if (createdAtStr != null) {
      accountStart = DateTime.parse(createdAtStr).toLocal();
      accountStart = DateTime(accountStart.year, accountStart.month, accountStart.day);
    }

    for (int i = 1; i <= 30; i++) {
      final d = today.subtract(Duration(days: i));
      final dayOnly = DateTime(d.year, d.month, d.day);
      if (dayOnly.isBefore(accountStart)) continue; // account তৈরি হওয়ার আগের দিন — skip
      await _writeDayJournal(userId, d);
    }

    final prevMonth = DateTime(today.year, today.month - 1, 1);
    if (!prevMonth.isBefore(DateTime(accountStart.year, accountStart.month, 1))) {
      await _writeMonthJournal(userId, prevMonth);
    }

    if (today.month == 1 && (today.year - 1) >= accountStart.year) {
      await _writeYearJournal(userId, today.year - 1);
    }

    print('JOURNAL SYNC DONE (as of $todayStr, account started ${accountStart.toIso8601String().split('T')[0]})');
  }


  static Future<bool> _factsExist(String userId, String date) async {
    final row = await supabase
        .from('insight_facts')
        .select('id')
        .eq('user_id', userId)
        .eq('entry_date', date)
        .limit(1);
    return row.isNotEmpty;
  }

  static Future<void> _extractInsightFacts(String userId, String date, String convo) async {
    if (await _factsExist(userId, date)) return;

    final raw = await _askOllama(
      "Extract ONLY explicit numeric activities the USER mentioned about their day, from lines starting with 'User:'. "
          "Only include things with a clear NUMBER (hours spent, count of something). Ignore feelings, moods, opinions.\n"
          "Examples:\n"
          "'I studied for 3 hours' -> {\"category\": \"study\", \"value\": 3, \"unit\": \"hours\"}\n"
          "'I read 2 books this week' -> {\"category\": \"books\", \"value\": 2, \"unit\": \"count\"}\n"
          "'traveled to 1 new place' -> {\"category\": \"travel\", \"value\": 1, \"unit\": \"count\"}\n"
          "If the same category appears more than once, merge into ONE final total.\n"
          "If nothing with an explicit number was mentioned, return [].\n"
          "Respond ONLY with a raw JSON array: [{\"category\": \"snake_case\", \"value\": number, \"unit\": \"hours_or_count\"}]. No markdown, no explanation.",
      convo,
    );

    try {
      final clean = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final List<dynamic> facts = jsonDecode(clean);
      if (facts.isEmpty) return;

      final rows = facts
          .where((f) => f['category'] != null && f['value'] != null && f['unit'] != null)
          .map((f) => {
        'user_id': userId,
        'entry_date': date,
        'category': f['category'],
        'value': f['value'],
        'unit': f['unit'],
      })
          .toList();

      if (rows.isNotEmpty) {
        await supabase.from('insight_facts').insert(rows);
        print('SAVED ${rows.length} insight facts for $date');
      }
    } catch (e) {
      print('INSIGHT EXTRACT ERROR for $date: $e');
    }
  }

  /// period অনুযায়ী start date বের করে ('week' = এই সপ্তাহের সোমবার, ইত্যাদি)
  static DateTime periodStart(String period, DateTime ref) {
    if (period == 'week') {
      return ref.subtract(Duration(days: ref.weekday - 1));
    } else if (period == 'month') {
      return DateTime(ref.year, ref.month, 1);
    } else {
      return DateTime(ref.year, 1, 1);
    }
  }

  static Future<void> setGoal(String userId, String category, num target, String unit, String period) async {
    final start = periodStart(period, DateTime.now()).toIso8601String().split('T')[0];
    await supabase.from('goals').insert({
      'user_id': userId,
      'category': category,
      'target': target,
      'unit': unit,
      'period': period,
      'period_start': start,
    });
  }
}