import 'package:flutter/material.dart';

class DeviceCard extends StatelessWidget {
  final String name;
  final String deviceId;
  final bool isOnline;
  final int activeSessions;
  final VoidCallback? onTap;

  const DeviceCard({
    super.key,
    required this.name,
    required this.deviceId,
    this.isOnline = false,
    this.activeSessions = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isOnline
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.computer,
                  color: isOnline
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isOnline ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isOnline ? '在线' : '离线',
                          style: TextStyle(
                            color: isOnline ? Colors.green : Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                        if (activeSessions > 0) ...[
                          const SizedBox(width: 12),
                          Text(
                            '$activeSessions 个会话',
                            style: TextStyle(color: Colors.grey[400], fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
