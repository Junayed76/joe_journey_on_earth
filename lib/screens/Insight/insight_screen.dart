import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';

enum InsightPeriod { week, month, year }

class InsightScreen extends StatefulWidget {
  const InsightScreen({super.key});
  @override
  State<InsightScreen> createState() => _InsightScreenState();
}

class _InsightScreenState extends State<InsightScreen> {
  final supabase = Supabase.instance.client;
  InsightPeriod _period = InsightPeriod.week;
  bool _loading = true;
  Map<String, Map<String, num>> _totals = {};
  Map<String, String> _units = {};
  List<Map<String, dynamic>> _goals = [];
  int _daysJournaled = 0;
  int _totalDaysInPeriod = 0;

  int _currentStreak = 0;
  int _longestStreak = 0;
  Set<String> _last7Days = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime _periodStart(DateTime ref) {
    switch (_period) {
      case InsightPeriod.week:
        return ref.subtract(Duration(days: ref.weekday - 1));
      case InsightPeriod.month:
        return DateTime(ref.year, ref.month, 1);
      case InsightPeriod.year:
        return DateTime(ref.year, 1, 1);
    }
  }

  int _fixedPeriodLength(DateTime start) {
    switch (_period) {
      case InsightPeriod.week:
        return 7;
      case InsightPeriod.month:
        final nextMonth = DateTime(start.year, start.month + 1, 1);
        return nextMonth.difference(start).inDays;
      case InsightPeriod.year:
        final isLeap =
            (start.year % 4 == 0 && start.year % 100 != 0) ||
            start.year % 400 == 0;
        return isLeap ? 366 : 365;
    }
  }

  DateTime _periodEnd(DateTime start, String period) {
    if (period == 'week') return start.add(const Duration(days: 6));
    if (period == 'month') return DateTime(start.year, start.month + 1, 0);
    return DateTime(start.year, 12, 31);
  }

  Map<String, int> _computeStreaks(Set<String> journaledDates, DateTime now) {
    String toStr(DateTime d) => d.toIso8601String().split('T')[0];

    int current = 0;
    DateTime cursor = DateTime(now.year, now.month, now.day);
    if (!journaledDates.contains(toStr(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (journaledDates.contains(toStr(cursor))) {
      current++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    final sortedDates = journaledDates.map((s) => DateTime.parse(s)).toList()
      ..sort();
    int longest = 0;
    int run = 0;
    DateTime? prev;
    for (final d in sortedDates) {
      if (prev != null && d.difference(prev).inDays == 1) {
        run++;
      } else {
        run = 1;
      }
      if (run > longest) longest = run;
      prev = d;
    }

    return {'current': current, 'longest': longest};
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final userId = supabase.auth.currentUser!.id;
    final now = DateTime.now();
    final start = _periodStart(now);
    final startStr = start.toIso8601String().split('T')[0];
    final todayStr = now.toIso8601String().split('T')[0];

    // Category totals (period অনুযায়ী)
    final facts = await supabase
        .from('insight_facts')
        .select('category, value, unit')
        .eq('user_id', userId)
        .gte('entry_date', startStr)
        .lte('entry_date', todayStr);

    final Map<String, Map<String, num>> totals = {};
    final Map<String, String> units = {};
    for (final f in List<Map<String, dynamic>>.from(facts)) {
      final cat = f['category'].toString();
      final val = (f['value'] as num);
      totals[cat] = {'value': (totals[cat]?['value'] ?? 0) + val};
      units[cat] = f['unit'].toString();
    }

    // Days journaled — এই period-এর মধ্যে
    final journalDaysInPeriod = await supabase
        .from('journal_entries')
        .select('entry_date')
        .eq('user_id', userId)
        .eq('period_type', 'day')
        .eq('is_placeholder', false)
        .gte('entry_date', startStr)
        .lte('entry_date', todayStr);

    // Streak হিসাব করার জন্য — সব journaled date (period-independent)
    final allJournaledData = await supabase
        .from('journal_entries')
        .select('entry_date')
        .eq('user_id', userId)
        .eq('period_type', 'day')
        .eq('is_placeholder', false)
        .order('entry_date', ascending: false);

    final journaledDates = List<Map<String, dynamic>>.from(
      allJournaledData,
    ).map((e) => e['entry_date'].toString()).toSet();

    final streaks = _computeStreaks(journaledDates, now);

    // Goals
    final goalsData = await supabase
        .from('goals')
        .select('category, target, unit, period, period_start')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final goalsList = <Map<String, dynamic>>[];
    for (final g in List<Map<String, dynamic>>.from(goalsData)) {
      final gStart = DateTime.parse(g['period_start'].toString());
      final gEnd = _periodEnd(gStart, g['period'].toString());
      if (now.isAfter(gEnd)) continue;

      final gStartStr = gStart.toIso8601String().split('T')[0];
      final progressData = await supabase
          .from('insight_facts')
          .select('value')
          .eq('user_id', userId)
          .eq('category', g['category'])
          .gte('entry_date', gStartStr)
          .lte('entry_date', todayStr);

      num progress = 0;
      for (final p in List<Map<String, dynamic>>.from(progressData)) {
        progress += (p['value'] as num);
      }

      goalsList.add({
        'category': g['category'],
        'target': g['target'],
        'unit': g['unit'],
        'progress': progress,
      });
    }

    if (!mounted) return;
    setState(() {
      _totals = totals;
      _units = units;
      _daysJournaled = List.from(journalDaysInPeriod).length;
      _totalDaysInPeriod = _fixedPeriodLength(start);
      _goals = goalsList;
      _currentStreak = streaks['current']!;
      _longestStreak = streaks['longest']!;
      _last7Days = journaledDates;
      _loading = false;
    });
  }

  String _label(String cat) => cat.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: InsightPeriod.values.map((p) {
                      final label = {
                        InsightPeriod.week: 'Week',
                        InsightPeriod.month: 'Month',
                        InsightPeriod.year: 'Year',
                      }[p]!;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _period == p,
                          onSelected: (_) {
                            setState(() => _period = p);
                            _load();
                          },
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // ===== Streak card =====
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.appBarBg, Color(0xFF3A2E4A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.local_fire_department,
                              color: AppColors.terracotta,
                              size: 32,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '$_currentStreak',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                'দিনের streak',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // ... বাকি dot row অংশ অপরিবর্তিত
                        const SizedBox(height: 14),
                        Row(
                          children: List.generate(7, (i) {
                            final d = DateTime.now().subtract(
                              Duration(days: 6 - i),
                            );
                            final dStr = d.toIso8601String().split('T')[0];
                            final done = _last7Days.contains(dStr);
                            const dayLetters = [
                              'S',
                              'M',
                              'T',
                              'W',
                              'T',
                              'F',
                              'S',
                            ];
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Column(
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: done
                                          ? AppColors.terracotta
                                          : Colors.white.withValues(alpha: 0.15),
                                    ),
                                    child: done
                                        ? const Icon(
                                            Icons.check,
                                            size: 14,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    dayLetters[d.weekday % 7],
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.white.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.emoji_events,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'সর্বোচ্চ streak: $_longestStreak দিন',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ===== Days journaled this period =====
                  Card(
                    color: AppColors.terracottaSoft,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            color: AppColors.terracottaSoft,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            "$_daysJournaled/$_totalDaysInPeriod দিন journal লেখা হয়েছে",
                            style: GoogleFonts.spaceGrotesk(
                              fontWeight: FontWeight.w700,
                              color: AppColors.streakAccent,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ===== Goals =====
                  if (_goals.isNotEmpty) ...[
                    const Text(
                      "Goals",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._goals.map((g) {
                      final progress = g['progress'] as num;
                      final target = g['target'] as num;
                      final ratio = target > 0
                          ? (progress / target).clamp(0, 1).toDouble()
                          : 0.0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _label(g['category']),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: ratio,
                                minHeight: 8,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "${progress.toStringAsFixed(progress % 1 == 0 ? 0 : 1)}/${target.toStringAsFixed(target % 1 == 0 ? 0 : 1)} ${g['unit']}",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                  ],

                  // ===== Activity totals + chart =====
                  const Text(
                    "Activity totals",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_totals.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        "এই সময়ে কোনো activity data পাওয়া যায়নি।",
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  else ...[
                    SizedBox(
                      height: 180,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY:
                              (_totals.values
                                          .map((v) => v['value']!)
                                          .reduce((a, b) => a > b ? a : b) *
                                      1.2)
                                  .toDouble(),
                          barTouchData: BarTouchData(enabled: true),
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final keys = _totals.keys.toList();
                                  final idx = value.toInt();
                                  if (idx < 0 || idx >= keys.length)
                                    return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      _label(keys[idx]),
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          barGroups: _totals.entries
                              .toList()
                              .asMap()
                              .entries
                              .map((entry) {
                                final idx = entry.key;
                                final value = entry.value.value['value']!
                                    .toDouble();
                                return BarChartGroupData(
                                  x: idx,
                                  barRods: [
                                    BarChartRodData(
                                      toY: value,
                                      color: AppColors.terracottaSoft,
                                      width: 22,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ],
                                );
                              })
                              .toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ..._totals.entries.map((e) {
                      final unit = _units[e.key] ?? '';
                      final value = e.value['value']!;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(_label(e.key)),
                          trailing: Text(
                            "${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} $unit",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.terracottaSoft,                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
    );
  }
}
