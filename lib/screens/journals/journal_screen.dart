import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/journal_writer_service.dart';
import '../../theme/app_theme.dart';
import '../Insight/insight_screen.dart';

enum JournalFilter { day, month, year }

class JournalScreen extends StatefulWidget {




  const JournalScreen({super.key});
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalEntry {
  final String date;
  final String type;
  final String content;
  final bool isPlaceholder;
  _JournalEntry({required this.date, required this.type, required this.content, this.isPlaceholder = false});

}

class _JournalScreenState extends State<JournalScreen> {

  String _title(String content) {
    final sentences = content.split(RegExp(r'(?<=[.!?])\s+'));
    var title = sentences.first.trim();
    if (title.length > 55) title = '${title.substring(0, 55)}...';
    return title;
  }

  String _snippet(String content) {
    final sentences = content.split(RegExp(r'(?<=[.!?])\s+'));
    if (sentences.length <= 1) return '';
    final rest = sentences.skip(1).join(' ').trim();
    return rest.length > 90 ? '${rest.substring(0, 90)}...' : rest;
  }

  static const _dayAbbr = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  static const _monthAbbr = [
    'JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'
  ];

  final supabase = Supabase.instance.client;
  JournalFilter _filter = JournalFilter.day;
  bool _loading = true;   // শুধু প্রথমবার, যখন কোনো data-ই নেই
  bool _syncing = false;  // background sync চলছে কিনা — ছোট indicator-এর জন্য
  List<_JournalEntry> _entries = [];

  bool _searchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  bool _isSearchMode = false;

  static const _monthNames = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // ১) আগে যা data আছে সাথে সাথে দেখাও (fast)
    await _loadEntries();

    // ২) তারপর background-এ sync চালাও, UI block না করে
    final userId = supabase.auth.currentUser!.id;
    if (mounted) setState(() => _syncing = true);
    await JournalWriterService.syncJournals(userId);
    if (mounted) setState(() => _syncing = false);

    // ৩) sync শেষে নতুন journal থাকলে সেটাও দেখাও
    await _loadEntries();
  }

  String _fmtDate(String isoDate) {
    final d = DateTime.parse(isoDate);
    if (_filter == JournalFilter.year) return d.year.toString();
    if (_filter == JournalFilter.month) return "${_monthNames[d.month - 1]} ${d.year}";
    return "${_monthNames[d.month - 1].substring(0, 3)} ${d.day}, ${d.year}";
  }

  Future<void> _loadEntries() async {
    final userId = supabase.auth.currentUser!.id;
    final firstLoad = _entries.isEmpty;
    if (mounted && firstLoad) setState(() => _loading = true);

    var query = supabase.from('journal_entries').select('entry_date, period_type, content, is_placeholder').eq('user_id', userId);
    if (_isSearchMode) {
      final text = _searchController.text.trim();
      if (text.isNotEmpty) query = query.ilike('content', '%$text%');
      if (_rangeStart != null && _rangeEnd != null) {
        final start = _rangeStart!.toIso8601String().split('T')[0];
        final end = _rangeEnd!.toIso8601String().split('T')[0];
        query = query.gte('entry_date', start).lte('entry_date', end);
      }
    } else {
      query = query.eq('period_type', _filter.name);
    }

    final data = await query.order('entry_date', ascending: false);
    final list = List<Map<String, dynamic>>.from(data);

    if (!mounted) return;
    setState(() {
      _entries = list
          .map((e) => _JournalEntry(
        date: e['entry_date'].toString(),
        type: e['period_type'].toString(),
        content: e['content'].toString(),
        isPlaceholder: e['is_placeholder'] == true,
      ))
          .toList();
      _loading = false;
    });
  }

  void _applySearch() {
    setState(() => _isSearchMode = true);
    _loadEntries();
  }

  void _clearSearch() {
    setState(() {
      _isSearchMode = false;
      _searchController.clear();
      _rangeStart = null;
      _rangeEnd = null;
      _searchOpen = false;
    });
    _loadEntries();
  }

  // ছোট compact popup dialog — full screen picker না
  Future<void> _openDateRangeDialog() async {
    DateTime? tempStart = _rangeStart;
    DateTime? tempEnd = _rangeEnd;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            String fmt(DateTime? d) => d == null ? 'Select' : "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

            return AlertDialog(
              title: const Text('Filter by date'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('From'),
                    trailing: Text(fmt(tempStart)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDate: tempStart ?? DateTime.now(),
                      );
                      if (picked != null) setDialogState(() => tempStart = picked);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('To'),
                    trailing: Text(fmt(tempEnd)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDate: tempEnd ?? DateTime.now(),
                      );
                      if (picked != null) setDialogState(() => tempEnd = picked);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _rangeStart = null;
                      _rangeEnd = null;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Clear'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _rangeStart = tempStart;
                      _rangeEnd = tempEnd;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openJournalDetail(_JournalEntry e) {
    final controller = TextEditingController(text: e.content);
    bool isEditing = false;
    bool saving = false;
    final d = DateTime.parse(e.date);
    final daysAgo = DateTime.now().difference(DateTime(d.year, d.month, d.day)).inDays;
    final agoLabel = daysAgo == 0
        ? 'আজ'
        : daysAgo == 1
        ? 'গতকাল'
        : '$daysAgo দিন আগে';
    final title = e.isPlaceholder ? 'কিছু লেখা হয়নি' : _title(e.content);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> save() async {
            final newContent = controller.text.trim();
            if (newContent.isEmpty) return;
            setDialogState(() => saving = true);
            try {
              final userId = supabase.auth.currentUser!.id;
              await supabase
                  .from('journal_entries')
                  .update({'content': newContent, 'edited': true, 'is_placeholder': false})
                  .eq('user_id', userId)
                  .eq('entry_date', e.date)
                  .eq('period_type', e.type);

              if (!mounted) return;
              setState(() {
                final idx = _entries.indexWhere((x) => x.date == e.date && x.type == e.type);
                if (idx != -1) {
                  _entries[idx] = _JournalEntry(date: e.date, type: e.type, content: newContent, isPlaceholder: false);
                }
              });
              if (context.mounted) Navigator.pop(context);
            } catch (err) {
              setDialogState(() => saving = false);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Save করা যায়নি, আবার চেষ্টা করো।')),
                );
              }
            }
          }

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            backgroundColor: AppColors.background,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textDark, height: 1.3),
                        ),
                      ),
                      Row(
                        children: [
                          if (!isEditing)
                            InkWell(
                              onTap: () => setDialogState(() => isEditing = true),
                              child: Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(color: AppColors.terracottaSoft, borderRadius: BorderRadius.circular(8)),
                                child: Icon(Icons.edit, size: 16, color: AppColors.terracotta),
                              ),
                            ),
                          InkWell(
                            onTap: () => Navigator.pop(context),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(Icons.close, size: 20, color: AppColors.textMuted),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(agoLabel, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: isEditing
                          ? TextField(
                        controller: controller,
                        maxLines: null,
                        autofocus: true,
                        style: TextStyle(fontSize: 14.5, height: 1.6, color: AppColors.textDark),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      )
                          : Text(controller.text, style: TextStyle(fontSize: 14.5, height: 1.6, color: AppColors.textDark)),
                    ),
                  ),
                  if (isEditing) ...[
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: saving
                              ? null
                              : () {
                            controller.text = e.content;
                            setDialogState(() => isEditing = false);
                          },
                          child: Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: saving ? null : save,
                          child: saving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: 'Insights',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const InsightScreen()));
            },
          ),
          IconButton(
            icon: Icon(_searchOpen ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searchOpen = !_searchOpen);
              if (!_searchOpen) _clearSearch();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_syncing)
            const LinearProgressIndicator(minHeight: 2),

          if (_searchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.calendar_month,
                      color: (_rangeStart != null || _rangeEnd != null) ? Colors.deepPurple : null,
                    ),
                    onPressed: _openDateRangeDialog,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search journal text...',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onSubmitted: (_) => _applySearch(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _applySearch,
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: JournalFilter.values.map((f) {
                  final label = {JournalFilter.day: 'Day', JournalFilter.month: 'Month', JournalFilter.year: 'Year'}[f]!;
                  final selected = _filter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _filter = f);
                        _loadEntries();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),

          const SizedBox(height: 8),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                ? const Center(child: Text("কোনো journal পাওয়া যায়নি।"))
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final e = _entries[index];
                final d = DateTime.parse(e.date);
                final bgColor = AppColors.cardColors[index % AppColors.cardColors.length];
                final accentColor = AppColors.cardAccents[index % AppColors.cardAccents.length];
                final title = e.isPlaceholder ? 'কিছু লেখা হয়নি' : _title(e.content);
                final snippet = e.isPlaceholder ? e.content : _snippet(e.content);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.cardBorder, width: 1),
                    boxShadow: [
                      BoxShadow(color: AppColors.cardShadow, blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _openJournalDetail(e),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Date badge
                          Container(
                            width: 52,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.dateBadgeBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Text(_dayAbbr[d.weekday - 1],
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.dateBadgeText)),
                                const SizedBox(height: 2),
                                Text('${d.day}',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.dateBadgeText)),
                                const SizedBox(height: 2),
                                Text(_monthAbbr[d.month - 1],
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.dateBadgeText)),
                              ],
                            ),
                          ),                          const SizedBox(width: 12),
                          // Title + snippet
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textDark,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (snippet.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    snippet,
                                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}