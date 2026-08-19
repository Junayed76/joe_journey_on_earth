import 'package:flutter/material.dart';
import '../../services/story_service.dart';
import '../../theme/app_theme.dart';

class ComposeStoryScreen extends StatefulWidget {
  const ComposeStoryScreen({super.key});
  @override
  State<ComposeStoryScreen> createState() => _ComposeStoryScreenState();
}

class _ComposeStoryScreenState extends State<ComposeStoryScreen> {
  final _controller = TextEditingController();
  String? _sourceDate;
  bool _publishing = false;

  Future<void> _pickJournal() async {
    final journals = await StoryService.fetchMyJournals();
    if (!mounted) return;

    if (journals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('তোমার এখনো কোনো journal নেই publish করার মতো।')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('তোমার journal থেকে বেছে নাও', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: journals.length,
                itemBuilder: (context, i) {
                  final j = journals[i];
                  final content = j['content'].toString();
                  final preview = content.length > 60 ? '${content.substring(0, 60)}...' : content;
                  return ListTile(
                    title: Text(j['entry_date'].toString(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text(preview, style: const TextStyle(fontSize: 12.5)),
                    onTap: () {
                      setState(() {
                        _controller.text = content;
                        _sourceDate = j['entry_date'].toString();
                      });
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _publish() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _publishing = true);
    try {
      await StoryService.publish(text, sourceDate: _sourceDate);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _publishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Publish করা যায়নি, আবার চেষ্টা করো।')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Write something'),
        actions: [
          TextButton(
            onPressed: _publishing ? null : _publish,
            child: _publishing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Publish', style: TextStyle(color: AppColors.terracotta, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              icon: Icon(Icons.menu_book_outlined, size: 18, color: AppColors.terracotta),
              label: Text('Publish journal', style: TextStyle(color: AppColors.terracotta)),
              style: OutlinedButton.styleFrom(side: BorderSide(color: AppColors.terracottaSoft)),
              onPressed: _pickJournal,
            ),
            if (_sourceDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Journal থেকে নেওয়া: $_sourceDate', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ),
            const SizedBox(height: 14),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 15, height: 1.5),
                decoration: InputDecoration(
                  hintText: 'কিছু লিখো...',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}