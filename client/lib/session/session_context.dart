import '../connection/connection_base.dart';

/// Carries the shared connection context to sub-pages (file browser, git, etc.).
class SessionContext {
  final ConnectionBase connection;
  final String targetDeviceId;

  SessionContext({required this.connection, required this.targetDeviceId});
}

/// Arguments for the file preview route.
class FilePreviewArgs {
  final SessionContext sessionContext;
  final String filePath;
  final String fileName;

  FilePreviewArgs({
    required this.sessionContext,
    required this.filePath,
    required this.fileName,
  });
}

/// Arguments for git sub-routes.
class GitRouteArgs {
  final SessionContext sessionContext;
  final String projectDir;

  GitRouteArgs({required this.sessionContext, required this.projectDir});
}
