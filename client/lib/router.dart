import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'ui/pages/device_list_page.dart';
import 'ui/pages/session_page.dart';
import 'ui/pages/pairing_page.dart';
import 'ui/pages/settings_page.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const DeviceListPage(),
    ),
    GoRoute(
      path: '/pair',
      builder: (context, state) => const PairingPage(),
    ),
    GoRoute(
      path: '/session/:deviceId',
      builder: (context, state) {
        final deviceId = state.pathParameters['deviceId']!;
        return SessionPage(deviceId: deviceId);
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
  ],
);
