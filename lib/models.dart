import 'dart:convert';

/// 巡逻点（一个 NFC 标签对应一个巡逻点）
class Checkpoint {
  final int? id;
  final String tagId;
  final String name;
  final DateTime createdAt;

  /// GPS position recorded at the checkpoint (null = not recorded yet).
  final double? lat;
  final double? lng;

  Checkpoint(
      {this.id,
      required this.tagId,
      required this.name,
      DateTime? createdAt,
      this.lat,
      this.lng})
      : createdAt = createdAt ?? DateTime.now();

  bool get hasLocation => lat != null && lng != null;

  Map<String, Object?> toMap() => {
        'id': id,
        'tag_id': tagId,
        'name': name,
        'created_at': createdAt.millisecondsSinceEpoch,
        'lat': lat,
        'lng': lng,
      };

  factory Checkpoint.fromMap(Map<String, Object?> m) => Checkpoint(
        id: m['id'] as int,
        tagId: m['tag_id'] as String,
        name: m['name'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
      );
}

/// 一条打卡记录
class CheckinLog {
  final int? id;
  final String tagId;
  final String checkpointName;
  final String guardName;
  final DateTime time;

  /// 标签是否已登记为巡逻点
  final bool known;

  /// Whether this check-in was randomly selected for photo proof.
  final bool photoRequired;

  /// Local path of the proof photo, or null if none was taken.
  final String? photoPath;

  /// Where the phone was when checking in (null = GPS check off / unavailable).
  final double? lat;
  final double? lng;

  /// Metres from the checkpoint's recorded position.
  final double? distanceM;

  /// GPS check result: 'ok', 'far', 'mock', 'none' (no fix), 'noref' (checkpoint has no
  /// recorded position), or null when the GPS check is off.
  final String? gpsStatus;

  CheckinLog({
    this.id,
    required this.tagId,
    required this.checkpointName,
    required this.guardName,
    required this.time,
    required this.known,
    this.photoRequired = false,
    this.photoPath,
    this.lat,
    this.lng,
    this.distanceM,
    this.gpsStatus,
  });

  /// GPS says the guard wasn't at the checkpoint (only stored in "flag" mode).
  bool get gpsProblem => gpsStatus == 'far' || gpsStatus == 'mock';

  bool get photoMissing => photoRequired && photoPath == null;

  Map<String, Object?> toMap() => {
        'id': id,
        'tag_id': tagId,
        'checkpoint_name': checkpointName,
        'guard_name': guardName,
        'time': time.millisecondsSinceEpoch,
        'known': known ? 1 : 0,
        'photo_required': photoRequired ? 1 : 0,
        'photo_path': photoPath,
        'lat': lat,
        'lng': lng,
        'distance_m': distanceM,
        'gps_status': gpsStatus,
      };

  factory CheckinLog.fromMap(Map<String, Object?> m) => CheckinLog(
        id: m['id'] as int,
        tagId: m['tag_id'] as String,
        checkpointName: m['checkpoint_name'] as String,
        guardName: m['guard_name'] as String,
        time: DateTime.fromMillisecondsSinceEpoch(m['time'] as int),
        known: (m['known'] as int) == 1,
        photoRequired: (m['photo_required'] as int? ?? 0) == 1,
        photoPath: m['photo_path'] as String?,
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        distanceM: (m['distance_m'] as num?)?.toDouble(),
        gpsStatus: m['gps_status'] as String?,
      );
}

/// An incident reported by a guard (broken fence, faulty light, …).
class Incident {
  final int? id;
  final DateTime time;
  final String guardName;
  final String category;
  final String? location;
  final String description;

  /// 'video' or 'photo'
  final String mediaType;
  final String? videoPath;
  final List<String> photoPaths;
  final String? voicePath;

  /// Chat IDs of owners who have received this report.
  final List<String> sentTo;

  Incident({
    this.id,
    required this.time,
    required this.guardName,
    required this.category,
    this.location,
    required this.description,
    required this.mediaType,
    this.videoPath,
    this.photoPaths = const [],
    this.voicePath,
    this.sentTo = const [],
  });

  List<String> get allMediaPaths => [
        if (videoPath != null) videoPath!,
        ...photoPaths,
        if (voicePath != null) voicePath!
      ];

  Map<String, Object?> toMap() => {
        'id': id,
        'time': time.millisecondsSinceEpoch,
        'guard_name': guardName,
        'category': category,
        'location': location,
        'description': description,
        'media_type': mediaType,
        'video_path': videoPath,
        'photo_paths': jsonEncode(photoPaths),
        'voice_path': voicePath,
        'sent_to': jsonEncode(sentTo),
      };

  factory Incident.fromMap(Map<String, Object?> m) => Incident(
        id: m['id'] as int,
        time: DateTime.fromMillisecondsSinceEpoch(m['time'] as int),
        guardName: m['guard_name'] as String,
        category: m['category'] as String,
        location: m['location'] as String?,
        description: m['description'] as String,
        mediaType: m['media_type'] as String,
        videoPath: m['video_path'] as String?,
        photoPaths:
            List<String>.from(jsonDecode(m['photo_paths'] as String) as List),
        voicePath: m['voice_path'] as String?,
        sentTo: List<String>.from(jsonDecode(m['sent_to'] as String) as List),
      );
}

/// A check-in that was refused because the GPS check failed (Block mode).
class RejectedCheckin {
  final int? id;
  final DateTime time;
  final String guardName;
  final String tagId;
  final String checkpointName;

  /// 'far', 'mock' or 'none' (no usable GPS).
  final String reason;
  final double? distanceM;
  final double? lat;
  final double? lng;

  RejectedCheckin({
    this.id,
    required this.time,
    required this.guardName,
    required this.tagId,
    required this.checkpointName,
    required this.reason,
    this.distanceM,
    this.lat,
    this.lng,
  });

  String? get mapsLink => lat == null
      ? null
      : 'https://maps.google.com/?q=${lat!.toStringAsFixed(6)},${lng!.toStringAsFixed(6)}';

  Map<String, Object?> toMap() => {
        'id': id,
        'time': time.millisecondsSinceEpoch,
        'guard_name': guardName,
        'tag_id': tagId,
        'checkpoint_name': checkpointName,
        'reason': reason,
        'distance_m': distanceM,
        'lat': lat,
        'lng': lng,
      };

  factory RejectedCheckin.fromMap(Map<String, Object?> m) => RejectedCheckin(
        id: m['id'] as int,
        time: DateTime.fromMillisecondsSinceEpoch(m['time'] as int),
        guardName: m['guard_name'] as String,
        tagId: m['tag_id'] as String,
        checkpointName: m['checkpoint_name'] as String,
        reason: m['reason'] as String,
        distanceM: (m['distance_m'] as num?)?.toDouble(),
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
      );
}
