import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../pages/device_list_page.dart';

/// Adaptive shell: on wide screens shows a persistent sidebar with
/// device list alongside the main content area. On narrow screens,
/// shows single-page navigation as before.
class AdaptiveShell extends StatelessWidget {
  final Widget child;

  const AdaptiveShell({super.key, required this.child});

  static const double tabletBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width >= tabletBreakpoint) {
      return _WideLayout(child: child);
    }
    return child;
  }
}

class _WideLayout extends StatefulWidget {
  final Widget child;

  const _WideLayout({required this.child});

  @override
  State<_WideLayout> createState() => _WideLayoutState();
}

class _WideLayoutState extends State<_WideLayout> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        // Sidebar: fixed-width device list
        Container(
          width: 280,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border(
              right: BorderSide(color: colorScheme.outlineVariant, width: 1),
            ),
          ),
          child: Column(
            children: [
              // Header
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Icon(
                      Icons.code,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'PocketClaude',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.settings, size: 18),
                      onPressed: () => context.push('/settings'),
                      tooltip: 'Settings',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Device list
              const Expanded(
                child: _SidebarDeviceList(),
              ),
            ],
          ),
        ),
        // Main content
        Expanded(child: widget.child),
      ],
    );
  }
}

/// A compact device list for the sidebar.
class _SidebarDeviceList extends StatefulWidget {
  const _SidebarDeviceList();

  @override
  State<_SidebarDeviceList> createState() => _SidebarDeviceListState();
}

class _SidebarDeviceListState extends State<_SidebarDeviceList> {
  @override
  void initState() {
    super.initState();
    // Navigate to device list on mount to populate presence
  }

  @override
  Widget build(BuildContext context) {
    // Use the full DeviceListPage in a compact form
    // But since it's a full page, we'll just link to it
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Add device button
          OutlinedButton.icon(
            onPressed: () => context.push('/pair'),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Device'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
          const SizedBox(height: 12),
          // Navigation links
          _SidebarTile(
            icon: Icons.phone_android,
            label: 'Devices',
            onTap: () => context.go('/'),
          ),
          _SidebarTile(
            icon: Icons.settings,
            label: 'Settings',
            onTap: () => context.push('/settings'),
          ),
          const SizedBox(height: 16),
          // Info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick Start',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 4),
                Text(
                  '1. Add a device via QR scan or paste\n'
                  '2. Tap a device to start a session\n'
                  '3. Use Files/Git buttons in session',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 18),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
