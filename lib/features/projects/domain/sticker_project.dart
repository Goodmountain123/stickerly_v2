import 'package:stickerly_v2/features/projects/domain/canvas_preset.dart';
import 'package:stickerly_v2/features/projects/domain/project_item.dart';
import 'package:uuid/uuid.dart';

class StickerProject {
  const StickerProject({
    required this.id,
    required this.title,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.createdAt,
    required this.updatedAt,
    this.thumbnailPath,
    this.background,
    this.stickerItems = const [],
    this.textItems = const [],
    this.lastTextColor = 'hsl(340 82% 62%)',
    this.textPalette = const [],
    this.lastGlowColor = 'hsl(205 100% 74%)',
    this.glowPalette = const [],
  });

  final String id;
  final String title;
  final int canvasWidth;
  final int canvasHeight;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? thumbnailPath;
  final ProjectBackground? background;
  final List<StickerItem> stickerItems;
  final List<TextItem> textItems;
  final String lastTextColor;
  final List<String> textPalette;
  final String lastGlowColor;
  final List<String> glowPalette;

  factory StickerProject.create({
    String? title,
    CanvasPreset preset = CanvasPreset.square,
    DateTime? now,
    Uuid uuid = const Uuid(),
  }) {
    final timestamp = now ?? DateTime.now();
    return StickerProject(
      id: 'prj_${uuid.v4()}',
      title: title?.trim().isNotEmpty == true ? title!.trim() : '제목 없는 프로젝트',
      canvasWidth: preset.width,
      canvasHeight: preset.height,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  factory StickerProject.fromJson(Map<String, dynamic> json) {
    final preset = CanvasPreset.fromJson(json['canvasType'] as String?);
    return StickerProject(
      id: json['id'] as String,
      title: json['title'] as String? ?? '제목 없는 프로젝트',
      canvasWidth: json['canvasWidth'] as int? ?? preset.width,
      canvasHeight: json['canvasHeight'] as int? ?? preset.height,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
      thumbnailPath: json['thumbnailPath'] as String?,
      background: json['background'] == null
          ? null
          : ProjectBackground.fromJson(
              json['background'] as Map<String, dynamic>,
            ),
      stickerItems: (json['stickerItems'] as List<dynamic>? ?? const [])
          .map((item) => StickerItem.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      textItems: (json['textItems'] as List<dynamic>? ?? const [])
          .map((item) => TextItem.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      lastTextColor: json['lastTextColor'] as String? ?? 'hsl(340 82% 62%)',
      textPalette: List<String>.from(
        json['textPalette'] as List<dynamic>? ?? const [],
      ),
      lastGlowColor: json['lastGlowColor'] as String? ?? 'hsl(205 100% 74%)',
      glowPalette: List<String>.from(
        json['glowPalette'] as List<dynamic>? ?? const [],
      ),
    );
  }

  StickerProject copyWith({
    String? title,
    int? canvasWidth,
    int? canvasHeight,
    DateTime? updatedAt,
    String? thumbnailPath,
    ProjectBackground? background,
    bool clearBackground = false,
    List<StickerItem>? stickerItems,
    List<TextItem>? textItems,
  }) {
    return StickerProject(
      id: id,
      title: title ?? this.title,
      canvasWidth: canvasWidth ?? this.canvasWidth,
      canvasHeight: canvasHeight ?? this.canvasHeight,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      background: clearBackground ? null : background ?? this.background,
      stickerItems: stickerItems ?? this.stickerItems,
      textItems: textItems ?? this.textItems,
      lastTextColor: lastTextColor,
      textPalette: textPalette,
      lastGlowColor: lastGlowColor,
      glowPalette: glowPalette,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'canvasWidth': canvasWidth,
    'canvasHeight': canvasHeight,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
    'background': background?.toJson(),
    'stickerItems': stickerItems.map((item) => item.toJson()).toList(),
    'textItems': textItems.map((item) => item.toJson()).toList(),
    'lastTextColor': lastTextColor,
    'textPalette': textPalette,
    'lastGlowColor': lastGlowColor,
    'glowPalette': glowPalette,
  };
}

class ProjectBackground {
  const ProjectBackground({
    required this.type,
    this.id,
    this.url,
    this.dataUrl,
    this.zoom = 1,
    this.x = 0,
    this.y = 0,
  });

  final String type;
  final String? id;
  final String? url;
  final String? dataUrl;
  final double zoom;
  final double x;
  final double y;

  factory ProjectBackground.fromJson(Map<String, dynamic> json) {
    final transform =
        json['transform'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    return ProjectBackground(
      type: json['type'] as String? ?? 'asset',
      id: json['id'] as String?,
      url: json['url'] as String?,
      dataUrl: json['dataUrl'] as String?,
      zoom: (transform['zoom'] as num?)?.toDouble() ?? 1,
      x: (transform['x'] as num?)?.toDouble() ?? 0,
      y: (transform['y'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    if (id != null) 'id': id,
    if (url != null) 'url': url,
    if (dataUrl != null) 'dataUrl': dataUrl,
    'transform': {'zoom': zoom, 'x': x, 'y': y},
  };
}
