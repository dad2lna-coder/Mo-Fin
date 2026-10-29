import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';

import '../../auth/repositories/session_repository.dart';
import '../../data/services/log_service.dart';
import '../../data/models/aggregated_item.dart';
import 'destinations.dart';

// MOFIN-PLUGIN-HOOK: PlaybackLauncher helper for plugin-triggered playback
class PlaybackLauncher {
  static Future<void> playItem(String itemId) async {
    final manager = GetIt.instance<PlaybackManager>();
    final client = GetIt.instance<MediaServerClient>();
    final serverId = GetIt.instance.isRegistered<SessionRepository>()
        ? GetIt.instance<SessionRepository>().activeServerId ?? client.baseUrl
        : client.baseUrl;
    try {
      await runPlaybackStart(null, () async {
        final itemData = await client.itemsApi.getItem(itemId);
        final item = AggregatedItem(
          id: itemId,
          serverId: serverId,
          rawData: itemData,
        );
        await manager.playItems([item]);
      });
    } catch (e) {
      GetIt.instance<LogService>().log(
        LogCategory.playback,
        'PlaybackLauncher: failed to launch item $itemId: $e',
        level: LogLevel.error,
      );
    }
  }

  static Future<void> playStream(String streamUrl, {String? title}) async {
    final manager = GetIt.instance<PlaybackManager>();
    final client = GetIt.instance<MediaServerClient>();
    final serverId = GetIt.instance.isRegistered<SessionRepository>()
        ? GetIt.instance<SessionRepository>().activeServerId ?? client.baseUrl
        : client.baseUrl;

    // Security check: Only allow streamUrl playback through a server-provided URL
    final isServerUrl = streamUrl.startsWith(client.baseUrl) ||
        streamUrl.startsWith('http://localhost') ||
        streamUrl.startsWith('https://localhost');
    if (!isServerUrl) {
      GetIt.instance<LogService>().log(
        LogCategory.playback,
        'PlaybackLauncher: rejected non-server streamUrl $streamUrl',
        level: LogLevel.warning,
      );
      return;
    }

    try {
      await runPlaybackStart(null, () async {
        final item = AggregatedItem(
          id: 'stream_${DateTime.now().millisecondsSinceEpoch}',
          serverId: serverId,
          rawData: {
            'Name': title ?? 'Direct Stream',
            'Type': 'Video',
            'Path': streamUrl,
            'MediaSources': [
              {
                'Id': 'stream_${DateTime.now().millisecondsSinceEpoch}',
                'Path': streamUrl,
                'Protocol': 'Http',
                'Container': streamUrl.contains('m3u8') ? 'm3u8' : 'mp4',
              }
            ],
          },
        );
        await manager.playItems([item]);
      });
    } catch (e) {
      GetIt.instance<LogService>().log(
        LogCategory.playback,
        'PlaybackLauncher: failed to launch stream $streamUrl: $e',
        level: LogLevel.error,
      );
    }
  }
}

typedef PlaybackStarter = Future<bool> Function(PlaybackLaunchSession? session);

Future<T> runPlaybackStart<T>(
  PlaybackLaunchSession? session,
  Future<T> Function() action,
) {
  return session == null ? action() : session.runIfActive(action);
}

/// Aborts a preparation whose launch is gone, the user backed out or another
/// launch took over.
void ensureLaunchStillWanted(PlaybackLaunchSession? session) {
  if (session != null && !session.isActive) {
    throw PlaybackStartupRecoveryAbortedException();
  }
}

PlaybackLaunchSession? _activeVideoLaunch;

Future<bool> launchPlayerWhilePreparing(
  BuildContext context, {
  required PlaybackManager manager,
  required String destination,
  required PlaybackStarter startPlayback,
}) async {
  if (!context.mounted) return false;

  if (destination != Destinations.videoPlayer) {
    final started = await startPlayback(null);
    if (!started || !context.mounted) return false;
    await context.push(destination);
    return true;
  }

  if (_activeVideoLaunch != null) {
    if (_videoPlayerRoutePresent(context)) {
      return false;
    }
    final stale = _activeVideoLaunch!;
    _activeVideoLaunch = null;
    stale._cancelled = true;
  }

  final session = PlaybackLaunchSession._();
  _activeVideoLaunch = session;

  Future<Object?> routeFuture;
  try {
    manager.beginPlaybackPreparation();
    manager.skipExternalRoutingOnce();
    routeFuture = context.push(Destinations.videoPlayer);
  } catch (_) {
    _activeVideoLaunch = null;
    manager.consumeSkipExternalRoutingOnce();
    manager.cancelPlaybackPreparation();
    rethrow;
  }

  unawaited(
    routeFuture.whenComplete(() {
      session._routeOpen = false;
      if (!session._startupFinished) {
        session._cancelled = true;
        manager.cancelPlaybackPreparation();
        if (identical(_activeVideoLaunch, session)) {
          _activeVideoLaunch = null;
        }
      }
    }),
  );

  try {
    await WidgetsBinding.instance.endOfFrame;
    if (!session.isActive) return false;

    final started = await startPlayback(session);
    final startedNothing =
        started && manager.bringupState.phase == PlaybackBringupPhase.preparing;
    if (startedNothing) {
      GetIt.instance<LogService>().log(
        LogCategory.playback,
        'Bringup: start reported success without starting playback, '
        'closing the player',
        level: LogLevel.warning,
      );
    }
    if (!started || startedNothing || !session.isActive) {
      if (started && !startedNothing) {
        unawaited(manager.stop(userInitiated: true));
      }
      if (context.mounted) {
        _closePlayerRoute(context, session);
      }
      manager.cancelPlaybackPreparation();
      return false;
    }

    session._startupFinished = true;
    if (manager.playbackDeferredToExternalPlayer) {
      if (context.mounted) {
        _closePlayerRoute(context, session);
      }
      await routeFuture;
      if (!context.mounted) return false;
      routeFuture = context.push(Destinations.externalPlayer);
    }

    await routeFuture;
    return true;
  } on _PlaybackLaunchCanceledException {
    manager.cancelPlaybackPreparation();
    return false;
  } catch (_) {
    if (context.mounted) {
      _closePlayerRoute(context, session);
    }
    manager.cancelPlaybackPreparation();
    rethrow;
  } finally {
    session._cancelled = true;
    if (identical(_activeVideoLaunch, session)) {
      _activeVideoLaunch = null;
    }
  }
}

bool _videoPlayerRoutePresent(BuildContext context) {
  try {
    bool present(List<RouteMatchBase> matches) {
      for (final match in matches) {
        if (match.matchedLocation == Destinations.videoPlayer) return true;
        if (match is ShellRouteMatch && present(match.matches)) return true;
      }
      return false;
    }

    return present(
      GoRouter.of(context).routerDelegate.currentConfiguration.matches,
    );
  } catch (_) {
    return true;
  }
}

void _closePlayerRoute(BuildContext context, PlaybackLaunchSession session) {
  if (!context.mounted || !session._routeOpen) return;
  final sourceRoute = ModalRoute.of(context);
  if (sourceRoute != null && !sourceRoute.isCurrent) {
    Navigator.of(context).pop();
  }
}

class PlaybackLaunchSession {
  PlaybackLaunchSession._();

  bool _routeOpen = true;
  bool _startupFinished = false;
  bool _cancelled = false;

  bool get isActive =>
      identical(_activeVideoLaunch, this) && _routeOpen && !_cancelled;

  Future<T> runIfActive<T>(Future<T> Function() action) {
    if (!isActive) {
      throw const _PlaybackLaunchCanceledException();
    }
    return action();
  }
}

class _PlaybackLaunchCanceledException implements Exception {
  const _PlaybackLaunchCanceledException();
}
