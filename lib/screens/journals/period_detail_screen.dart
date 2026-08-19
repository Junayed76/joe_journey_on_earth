import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class PeriodDetailScreen extends StatefulWidget {
  final String label;
  final DateTime start;
  final DateTime end;
  final bool isSingleDay;

  const PeriodDetailScreen({
    super.key,
    required this.label,
    required this.start,
    required this.end,
    required this.isSingleDay,
  });

  @override
  State<PeriodDetailScreen> createState() => _PeriodDetailScreenState();
}

class _PeriodDetailScreenState extends State<PeriodDetailScreen> {
  final supabase = Supabase.instance.client;
  bool _loading = true;

  String? _dayEntry;
  Map<String, int> _categoryTotals = {};
  String _summary = '';
  List<String> _highlights = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _iso(DateTime d) => d.toIso8601String().split('T')[0];

  Future<void> _load() async {
    setState(() => _loading = true);
    final userId = supabase.auth.currentUser!.id;

    if (widget.isSingleDay) {
      final entry = await supabase
          .from('journal_entries')
          .select('content')
          .eq('user_id', userId)
          .eq('entry_date', _iso(widget.start))
          .maybeSingle();

      setState(() {
        _dayEntry = entry?['content'] ?? "এই দিনের কোনো entry পাওয়া যায়নি।";
        _loading = false;
      });
      return;
    }

    // Week/Month/Year — aggregate insights
    final factsData = await supabase
        .from('daily_facts')
        .select('entry_date, category, duration_minutes, value, note')
        .eq('user_id', userId)
        .gte('entry_date', _iso(widget.start))
        .lte('entry_date', _iso(widget.end))
        .order('entry_date');

    final facts = List<Map<String, dynamic>>.from(factsData);

    final Map<String, int> totals = {};
    final List<Map<String, dynamic>> qualitative = [];
    for (final f in facts) {
      if (f['duration_minutes'] != null) {
        final cat = f['category'].toString();
        totals[cat] = (totals[cat] ?? 0) + (f['duration_minutes'] as int);
      } else if (f['value'] != null || f['note'] != null) {
        qualitative.add(f);
      }
    }

    final entriesData = await supabase
        .from('journal_entries')
        .select('entry_date, content')
        .eq('user_id', userId)
        .gte('entry_date', _iso(widget.start))
        .lte('entry_date', _iso(widget.end))
        .order('entry_date');
    final entries = List<Map<String, dynamic>>.from(entriesData);

    setState(() => _categoryTotals = totals);

    if (facts.isEmpty && entries.isEmpty) {
      setState(() {
        _summary = "এই সময়ের জন্য কোনো data নেই।";
        _loading = false;
      });
      return;
    }

    final factsSummaryText = totals.entries.map((e) => "${e.key}: ${e.value} minutes total").join('\n');
    final qualitativeText = qualitative.map((f) => "${f['entry_date']} - ${f['category']}: ${f['note'] ?? f['value']}").join('\n');
    final journalText = entries.map((e) => "${e['entry_date']}: ${e['content']}").join('\n\n');

    try {
      final response = await http.post(
        Uri.parse('http://10.0.2.2:11434/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'llama3.2',
          'messages': [
            {
              'role': 'system',
              'content':
              "You are analyzing a user's personal data to show them insights about themselves. Extract as much specific, concrete information as possible — exact numbers, patterns, notable moments. "
                  "Respond ONLY with raw JSON: {\"summary\": \"2-3 sentence narrative overview with specific numbers/patterns\", \"highlights\": [\"short specific fact\", \"up to 5\"]}. No markdown, no explanation."
            },
            {
              'role': 'user',
              'content': "Activity totals:\n$factsSummaryText\n\nOther facts:\n$qualitativeText\n\nJournal entries:\n$journalText"
            },
          ],
          'stream': false,
        }),
      );

      final data = jsonDecode(response.body);
      String raw = (data['message']['content'] ?? '{}').toString();
      raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final parsed = jsonDecode(raw);

      setState(() {
        _summary = parsed['summary'] ?? '';
        _highlights = List<String>.from(parsed['highlights'] ?? []);
      });
    } catch (e) {
      setState(() => _summary = "Summary generate করতে সমস্যা হয়েছে।");
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.label)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.isSingleDay)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_dayEntry ?? '', style: const TextStyle(fontSize: 16, height: 1.5)),
            )
          else ...[
            if (_summary.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_summary, style: const TextStyle(fontSize: 15, height: 1.5)),
              ),
            const SizedBox(height: 20),
            if (_categoryTotals.isNotEmpty) ...[
              const Text('Time Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    barGroups: _categoryTotals.entries.toList().asMap().entries.map((entry) {
                      return BarChartGroupData(
                        x: entry.key,
                        barRods: [
                          BarChartRodData(
                            toY: entry.value.value.toDouble(),
                            color: Colors.deepPurple,
                            width: 20,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      );
                    }).toList(),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final keys = _categoryTotals.keys.toList();
                            if (value.toInt() >= keys.length) return const SizedBox();
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(keys[value.toInt()], style: const TextStyle(fontSize: 10)),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (_highlights.isNotEmpty) ...[
              const Text('Highlights', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._highlights.map((h) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [const Text('•  '), Expanded(child: Text(h, style: const TextStyle(fontSize: 14)))],
                ),
              )),
            ],
          ],
        ],
      ),
    );
  }
}