import 'package:flutter/material.dart';
import '../../screens/Insight/insight_screen.dart';
import '../../screens/chat/chat_screen.dart';
import '../../screens/journals/journal_screen.dart';
import '../../theme/app_theme.dart';

import '../story/story_feed_screen.dart';
import '../settings/settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  final _screens = const [
    ChatScreen(),
    JournalScreen(),
    StoryFeedScreen(),
    InsightScreen(),
    SettingsScreen(),
  ];

  final _navItems = const [
    {'icon': Icons.chat_bubble_outline, 'activeIcon': Icons.chat_bubble},
    {'icon': Icons.menu_book_outlined, 'activeIcon': Icons.menu_book},
    {'icon': Icons.public_outlined, 'activeIcon': Icons.public},
    {'icon': Icons.bar_chart_outlined, 'activeIcon': Icons.bar_chart},
    {'icon': Icons.person_outline, 'activeIcon': Icons.person},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, -1)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_navItems.length, (i) {
                final selected = _index == i;
                final item = _navItems[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _index = i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Icon(
                      selected ? item['activeIcon'] as IconData : item['icon'] as IconData,
                      size: 24,
                      color: selected ? AppColors.terracotta : AppColors.terracotta.withOpacity(0.4),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}