import 'package:flutter/material.dart';

/// Horizontal tab bar for switching between open sessions.
class SessionTabBar extends StatelessWidget {
  final List<SessionTab> tabs;
  final String activeSessionId;
  final ValueChanged<String> onTabSelected;
  final VoidCallback onNewSession;
  final ValueChanged<String> onCloseSession;

  const SessionTabBar({
    super.key,
    required this.tabs,
    required this.activeSessionId,
    required this.onTabSelected,
    required this.onNewSession,
    required this.onCloseSession,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        itemCount: tabs.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 2),
        itemBuilder: (context, index) {
          if (index == tabs.length) {
            return _addButton(context);
          }
          final tab = tabs[index];
          final isActive = tab.sessionId == activeSessionId;
          return _sessionTab(context, tab, isActive);
        },
      ),
    );
  }

  Widget _sessionTab(BuildContext context, SessionTab tab, bool isActive) {
    return GestureDetector(
      onTap: () => onTabSelected(tab.sessionId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.surface
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 12,
                color: isActive
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => onCloseSession(tab.sessionId),
              child: Icon(
                Icons.close,
                size: 12,
                color: isActive ? null : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addButton(BuildContext context) {
    return GestureDetector(
      onTap: onNewSession,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        child: Icon(Icons.add, size: 16, color: Colors.grey),
      ),
    );
  }
}

class SessionTab {
  final String sessionId;
  final String label;

  const SessionTab({required this.sessionId, required this.label});
}
