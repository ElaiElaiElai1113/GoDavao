import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/notifications_service.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return const SizedBox.shrink();

    final service = NotificationService(sb);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: service.streamForUser(uid),
      builder: (context, snap) {
        final notifs = snap.data ?? const [];
        final unread = notifs.where((n) => n['read_at'] == null).length;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  showDragHandle: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  builder:
                      (_) => _NotificationsSheet(
                        notifs: notifs,
                        onMarkAll: () => service.markAllRead(),
                      ),
                );
              },
            ),
            if (unread > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NotificationsSheet extends StatelessWidget {
  final List<Map<String, dynamic>> notifs;
  final VoidCallback onMarkAll;
  const _NotificationsSheet({required this.notifs, required this.onMarkAll});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text(
              'Notifications',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            trailing: TextButton(
              onPressed: onMarkAll,
              child: const Text('Mark all read'),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child:
                notifs.isEmpty
                    ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No notifications yet.'),
                    )
                    : ListView.separated(
                      shrinkWrap: true,
                      itemCount: notifs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final n = notifs[i];
                        return ListTile(
                          leading: const Icon(Icons.notifications),
                          title: Text(n['title'] as String? ?? ''),
                          subtitle: Text(n['body'] as String? ?? ''),
                          dense: true,
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
