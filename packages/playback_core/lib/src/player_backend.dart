import 'letterbox_crop.dart';

enum SubtitleRendererMode { native, assOverlay }

/// The part of a live stream that can be sought back into, on the same clock
/// as the player's position: from the oldest moment the stream still keeps to
/// its live edge.
class LiveSeekWindow {
  const LiveSeekWindow({required this.start, required this.edge});

  final Duration start;
  final Duration edge;

  Duration get length => edge - start;
}

/// A caption track the player found inside the video itself, like the CEA-608
/// captions broadcasters carry in H.264 SEI data.
///
/// Servers don't list these as subtitle streams because nothing declares them
/// ahead of time, so they have no stream index and only exist once the player
/// has read far enough into the stream to find them.
class EmbeddedCaptionTrack {
  const EmbeddedCaptionTrack({
    required this.id,
    required this.label,
    this.language,
  });

  /// Identifies the track to the backend it came from. Only meaningful to that
  /// backend.
  final int id;

  /// What to show in a track menu, like "CC1".
  final String label;

  final String? language;

  /// Reads the caption tracks a platform player reports finding inside the
  /// video, as a list of `{id, label, language}` maps. An entry without a
  /// usable id is dropped rather than offered as a menu row that can't be
  /// selected.
  static List<EmbeddedCaptionTrack> listFromWire(dynamic value) {
    if (value is! List) return const [];
    final tracks = <EmbeddedCaptionTrack>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is! int || id <= 0) continue;
      final label = entry['label']?.toString() ?? '';
      final language = entry['language']?.toString() ?? '';
      tracks.add(
        EmbeddedCaptionTrack(
          id: id,
          label: label.isEmpty ? 'CC$id' : label,
          language: language.isEmpty ? null : language,
        ),
      );
    }
    return List.unmodifiable(tracks);
  }
}

/// A text rendition the player found in the stream itself, such as an HLS
/// `#EXT-X-MEDIA:TYPE=SUBTITLES` playlist. Unlike [EmbeddedCaptionTrack], the
/// id is a string the native player minted from the group and the index
/// inside that group. A position in a flattened list is not stable.
class NativeTextRendition {
  const NativeTextRendition({
    required this.id,
    required this.label,
    this.language,
    this.mimeType,
    this.selected = false,
  });

  final String id;
  final String label;
  final String? language;
  final String? mimeType;
  final bool selected;

  static List<NativeTextRendition> listFromWire(dynamic value) {
    if (value is! List) return const [];
    final tracks = <NativeTextRendition>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      final id = entry['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final label = entry['label']?.toString() ?? '';
      final language = entry['language']?.toString() ?? '';
      final mimeType = entry['mimeType']?.toString() ?? '';
      tracks.add(
        NativeTextRendition(
          id: id,
          label: label.isEmpty ? 'Subtitles' : label,
          language: language.isEmpty ? null : language,
          mimeType: mimeType.isEmpty ? null : mimeType,
          selected: entry['selected'] == true,
        ),
      );
    }
    return List.unmodifiable(tracks);
  }
}

/// `${groupKey.length}:$groupKey:$trackIndex`. The length prefix keeps a key
/// that itself contains colons, which HLS group ids do. The native player
/// builds the same string and selects by parsing it back, not by position.
String textRenditionId(String groupKey, int trackIndex) =>
    '${groupKey.length}:$groupKey:$trackIndex';

({String groupKey, int trackIndex})? parseTextRenditionId(String id) {
  final separator = id.indexOf(':');
  if (separator <= 0) return null;
  final length = int.tryParse(id.substring(0, separator));
  if (length == null || length < 0) return null;
  final keyStart = separator + 1;
  final keyEnd = keyStart + length;
  if (keyEnd >= id.length || id.codeUnitAt(keyEnd) != 0x3A) return null;
  final key = id.substring(keyStart, keyEnd);
  final index = int.tryParse(id.substring(keyEnd + 1));
  if (index == null || index < 0) return null;
  return (groupKey: key, trackIndex: index);
}

bool textRenditionLanguageMatches(String? track, String preferred) {
  if (track == null || track.isEmpty || preferred.isEmpty) return false;
  final left = track.trim().toLowerCase();
  final right = preferred.trim().toLowerCase();
  if (left == 'und' || right == 'und') return false;
  return left == right || left.startsWith(right) || right.startsWith(left);
}

/// The rendition [preferred] names, or null when none of them match. `en`
/// matches `eng` and `en-us`. CEA-608 is not in this list.
NativeTextRendition? chooseNativeTextRendition(
  List<NativeTextRendition> tracks,
  String preferred,
) {
  final language = preferred.trim().isEmpty ? 'en' : preferred.trim();
  for (final track in tracks) {
    if (textRenditionLanguageMatches(track.language, language)) return track;
  }
  return null;
}

/// Whether the chosen external subtitle is still being prepared, retries
/// included. False also covers a canceled or failed load, so it doesn't mean
/// the subtitle arrived, and it never waits for a cue to show. Backends opt in
/// by implementing this interface.
abstract interface class SubtitleLoadingBackend {
  bool get isSubtitleLoading;
  Stream<bool> get subtitleLoadingStream;
}

abstract class PlayerBackend {
  Future<void> play(
    dynamic mediaItem, {
    Duration startPosition = Duration.zero,
  });
  Future<void> resume();
  Future<void> pause();
  Future<void> stop();
  Future<void> seekTo(Duration position);

  Duration get position;
  Duration get duration;
  Duration get buffer;
  bool get isPlaying;
  bool get isBuffering;
  double get playbackSpeed;

  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<Duration> get bufferStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<bool> get completedStream;
  Stream<Map<String, dynamic>>? get errorStream => null;

  /// Whether the player has been told to play. Null on engines that don't
  /// expose their own intent, and callers then fall back to "not playing".
  ///
  /// This exists because `isPlaying` is derived: a viewer pause, a starved
  /// stream and a transient audio focus loss all read as not playing. Only a
  /// starved stream leaves this true.
  bool? get playWhenReady => null;

  Map<String, dynamic> getDeviceProfile({bool useProgressiveTranscode = false});

  Future<void> setPlaybackSpeed(double speed);
  Future<void> setAudioTrack(int index);
  Future<void> setSubtitleTrack(
    int index, {
    bool isBitmapSubtitle = false,
    String? subtitleCodec,
    bool isExternalSubtitle = false,
    String? externalSubtitleUrl,
  });
  Future<void> disableSubtitleTrack();

  /// Selects an independent text sidecar for the Android Media3 overlay.
  /// Backends without a separate subtitle layer leave it disabled.
  Future<void> setSecondarySubtitle({String? url, String? codec}) async {}
  Future<void> setSecondarySubtitleDelay(double seconds) async {}
  Future<void> configureSecondarySubtitleStyle({
    double? fontSize,
    double? verticalOffset,
    int? textColor,
  }) async {}
  Future<void> waitForTracksReady();
  Future<void> waitForEmbeddedSubtitleCount(int count);
  Future<void> setVolume(double volume);
  Future<void> setAudioDelay(double seconds);
  Future<void> setSubtitleDelay(double seconds);
  Future<void> addExternalSubtitle(
    String url, {
    String? title,
    String? language,
    String? codec,
  });
  Future<void> configureSubtitleStyle({
    int? textColor,
    int? backgroundColor,
    int? strokeColor,
    double? fontSize,
    int? fontWeight,
    double? verticalOffset,
  });

  Future<void> setSubtitleRendererMode(SubtitleRendererMode mode);

  bool get supportsRuntimeTrackSelection;

  /// Whether a direct-played source can switch audio tracks in place through
  /// [setAudioTrack]. When true the manager skips the PlaybackInfo round trip
  /// and player rebuild that a re-resolve costs, since every embedded track is
  /// already in the stream.
  bool get supportsDirectPlayAudioSwitch => false;

  int? get activeSubtitleTrackIndex => null;

  Future<int?> getActiveSubtitleTrackIndexAsync() async => null;

  bool get requiresStartupMediaReadyCheck => true;

  bool get nativelyHandlesStartPosition => false;

  /// Whether this backend requests and holds Android audio focus itself, like
  /// media3/ExoPlayer built with handleAudioFocus=true. When true, the Dart
  /// audio_session layer stays out of the way so the two do not fight over focus
  /// and pause each other.
  bool get managesAudioFocus => false;

  bool get canRenderBitmapSubtitles;

  /// Whether the player reads subtitle tracks out of the stream itself. A
  /// browser only shows what it is handed as its own file, so subtitles living
  /// inside the container have to be added the same way an external one is,
  /// even when nothing stripped them from the stream.
  bool get demuxesEmbeddedSubtitles => true;

  /// Caption tracks the player found inside the video, which no server stream
  /// list can describe. Empty on engines that don't decode them.
  List<EmbeddedCaptionTrack> get embeddedCaptionTracks => const [];

  /// Turns on one of [embeddedCaptionTracks]. Turning captions back off goes
  /// through [disableSubtitleTrack], the same as any other subtitle.
  Future<void> setEmbeddedCaptionTrack(int id) async {}

  /// Text renditions the player found in the container or HLS master, which
  /// are not CEA-608 captions and not server subtitle streams.
  List<NativeTextRendition> get nativeTextRenditions => const [];

  /// Selects one of [nativeTextRenditions]. A null or empty id clears that
  /// override without disabling text, so a caption track can be chosen next.
  /// Turning captions off still goes through [disableSubtitleTrack].
  Future<void> setNativeTextRendition(String? id) async {}

  /// Picks a live stream back up after the player ran out of media, returning
  /// whether it could. A live source has no end, so reaching one means the
  /// source starved, and the cheapest answer is to re-open it where the stream
  /// is now rather than tear the server session down. False means the engine
  /// did nothing, and the caller must escalate rather than wait for a recovery
  /// that is never coming.
  Future<bool> resumeLiveEdge() async => false;

  /// Where a live stream can be sought within, or null when it keeps nothing
  /// to go back to, as a tuner's raw transport stream doesn't.
  LiveSeekWindow? get liveSeekWindow => null;

  /// Fires when the player's own track list changes. Captions carried inside
  /// the video turn up part way through playback, so a menu built when the
  /// stream started has to be rebuilt when this fires.
  Stream<void> get tracksChangedStream => const Stream.empty();

  /// How long this player usually takes to render again after a seek. Only
  /// paces how often SyncPlay may correct: the cost it actually compensates
  /// for is measured from the player, never taken from here.
  Duration get typicalSeekLatency => const Duration(milliseconds: 1500);

  /// The longest a seek on this player may plausibly take. SyncPlay treats a
  /// gap larger than this as the client being genuinely late rather than as
  /// the seek still landing, and stops waiting on a seek that exceeds it.
  /// Backends that restart a transcode to seek need this much higher than the
  /// in-buffer seek a desktop player does.
  Duration get maxSeekLatency => const Duration(seconds: 8);

  /// Whether the rate can be changed a few percent mid-playback without the
  /// audio dropping or glitching. mpv and ExoPlayer stretch audio in place;
  /// the AVPlayer-based engines rebuild the audio pipeline on every rate write
  /// and cannot pass Dolby audio through at anything but 1x. SyncPlay only
  /// nudges the rate where this is true, and holds the player instead where
  /// it is not.
  bool get supportsSmoothRateChange => true;

  /// Detect encoded letterbox and crop it. Cover-zoom is not this.
  ///
  /// Desktop libmpv and Android Media3 ship a cropper. Aether / Tizen / HTML
  /// return [UnsupportedLetterboxCropper] until they implement [LetterboxCropper].
  LetterboxCropper get letterboxCropper => const UnsupportedLetterboxCropper();

  bool get supportsLetterboxCrop => letterboxCropper.isSupported;

  void dispose();
}
