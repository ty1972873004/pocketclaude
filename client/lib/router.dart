import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../session/session_context.dart';
import '../ui/pages/device_list_page.dart';
import '../ui/pages/file_browser_page.dart';
import '../ui/pages/git_diff_page.dart';
import '../ui/pages/git_log_page.dart';
import '../ui/pages/git_status_page.dart';
import '../ui/pages/pairing_page.dart';
import '../ui/pages/session_page.dart';
import '../ui/pages/settings_page.dart';
import '../ui/shells/adaptive_shell.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AdaptiveShell(child: child),
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
          routes: [
            GoRoute(
              path: 'files',
              builder: (context, state) {
                final ctx = state.extra! as SessionContext;
                return FileBrowserPage(sessionContext: ctx);
              },
            ),
            GoRoute(
              path: 'file-preview',
              builder: (context, state) {
                final args = state.extra! as FilePreviewArgs;
                return FilePreviewPage(
                  sessionContext: args.sessionContext,
                  filePath: args.filePath,
                  fileName: args.fileName,
                );
              },
            ),
            GoRoute(
              path: 'git',
              builder: (context, state) {
                final args = state.extra! as GitRouteArgs;
                return GitStatusPage(
                  sessionContext: args.sessionContext,
                  projectDir: args.projectDir,
                );
              },
            ),
            GoRoute(
              path: 'git-diff',
              builder: (context, state) {
                final args = state.extra! as GitRouteArgs;
                return GitDiffPage(
                  sessionContext: args.sessionContext,
                  projectDir: args.projectDir,
                );
              },
            ),
            GoRoute(
              path: 'git-log',
              builder: (context, state) {
                final args = state.extra! as GitRouteArgs;
                return GitLogPage(
                  sessionContext: args.sessionContext,
                  projectDir: args.projectDir,
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
        ),
      ],
    ),
  ],
);
