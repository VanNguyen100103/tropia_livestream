import 'package:dio/dio.dart';

/// URLs returned by Go backend for publishing a stream.
class PublishURLs {
  final String rtmp;
  final String whip;
  final String srt;

  PublishURLs({required this.rtmp, required this.whip, required this.srt});

  factory PublishURLs.fromJson(Map<String, dynamic> json) => PublishURLs(
        rtmp: json['rtmp'] as String? ?? '',
        whip: json['whip'] as String? ?? '',
        srt: json['srt'] as String? ?? '',
      );
}

/// URLs returned by Go backend for playing back a stream.
class PlaybackURLs {
  final String hls;
  final String flv;
  final String whep;

  PlaybackURLs({required this.hls, required this.flv, required this.whep});

  factory PlaybackURLs.fromJson(Map<String, dynamic> json) => PlaybackURLs(
        hls: json['hls'] as String? ?? '',
        flv: json['flv'] as String? ?? '',
        whep: json['whep'] as String? ?? '',
      );
}

class StreamInfo {
  final String id;
  final String sellerId;
  final String title;
  final String? description;
  final String? coverImageUrl;
  final String status;
  final int viewerCount;
  final int likeCount;
  final DateTime startedAt;

  StreamInfo({
    required this.id,
    required this.sellerId,
    required this.title,
    this.description,
    this.coverImageUrl,
    required this.status,
    required this.viewerCount,
    required this.likeCount,
    required this.startedAt,
  });

  factory StreamInfo.fromJson(Map<String, dynamic> json) => StreamInfo(
        id: json['id'] as String,
        sellerId: json['seller_id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        coverImageUrl: json['cover_image_url'] as String?,
        status: json['status'] as String? ?? 'live',
        viewerCount: (json['viewer_count'] as num?)?.toInt() ?? 0,
        likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
        startedAt: DateTime.parse(json['started_at'] as String),
      );
}

class SrsService {
  final Dio _dio;

  SrsService({required Dio dio}) : _dio = dio;

  /// Seller creates a new live stream session. Returns the session and
  /// publish URLs (RTMP/WHIP/SRT) the host should push to.
  Future<({StreamInfo session, PublishURLs publish})> createStream({
    required String title,
    String? description,
    String? coverImageUrl,
    String? category,
  }) async {
    final resp = await _dio.post(
      '/api/live/streams',
      data: {
        'title': title,
        if (description != null) 'description': description,
        if (coverImageUrl != null) 'cover_image_url': coverImageUrl,
        if (category != null) 'category': category,
      },
    );
    final data = resp.data as Map<String, dynamic>;
    return (
      session: StreamInfo.fromJson(data['session'] as Map<String, dynamic>),
      publish: PublishURLs.fromJson(data['publish'] as Map<String, dynamic>),
    );
  }

  /// Owner fetches publish URLs for an existing stream (e.g. after app restart).
  Future<PublishURLs> getPublishUrls(String streamId) async {
    final resp = await _dio.get('/api/live/streams/$streamId/publish');
    final data = resp.data as Map<String, dynamic>;
    return PublishURLs.fromJson(data['publish'] as Map<String, dynamic>);
  }

  /// Viewer fetches playback URLs.
  Future<({StreamInfo session, PlaybackURLs playback})> getPlayback(String streamId) async {
    final resp = await _dio.get('/api/live/streams/$streamId/playback');
    final data = resp.data as Map<String, dynamic>;
    return (
      session: StreamInfo.fromJson(data['session'] as Map<String, dynamic>),
      playback: PlaybackURLs.fromJson(data['playback'] as Map<String, dynamic>),
    );
  }

  Future<List<StreamInfo>> listActive() async {
    final resp = await _dio.get('/api/live/streams');
    final list = (resp.data as Map<String, dynamic>)['sessions'] as List;
    return list
        .map((e) => StreamInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> endStream(String streamId) async {
    await _dio.post('/api/live/streams/$streamId/end');
  }

  Future<void> join(String streamId) async {
    await _dio.post('/api/live/streams/$streamId/join');
  }

  Future<void> leave(String streamId) async {
    await _dio.post('/api/live/streams/$streamId/leave');
  }

  Future<void> like(String streamId) async {
    await _dio.post('/api/live/streams/$streamId/like');
  }
}
