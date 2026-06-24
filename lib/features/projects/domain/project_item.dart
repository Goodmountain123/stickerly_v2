import 'package:stickerly_v2/features/projects/domain/sticker_effects.dart';

sealed class ProjectItem {
  const ProjectItem({
    required this.id,
    required this.x,
    required this.y,
    required this.scale,
    required this.rotation,
    required this.zIndex,
  });

  final String id;
  final double x;
  final double y;
  final double scale;
  final double rotation;
  final int zIndex;

  Map<String, dynamic> toJson();
}

class StickerItem extends ProjectItem {
  const StickerItem({
    required super.id,
    required this.packId,
    required this.assetId,
    required super.x,
    required super.y,
    required super.zIndex,
    super.scale = 1,
    super.rotation = 0,
    this.flipX = false,
    this.flipY = false,
    this.effects = const StickerEffects(),
  });

  final String packId;
  final String assetId;
  final bool flipX;
  final bool flipY;
  final StickerEffects effects;

  StickerItem copyWith({
    double? x,
    double? y,
    double? scale,
    double? rotation,
    bool? flipX,
    bool? flipY,
    int? zIndex,
    StickerEffects? effects,
  }) {
    return StickerItem(
      id: id,
      packId: packId,
      assetId: assetId,
      x: x ?? this.x,
      y: y ?? this.y,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      flipX: flipX ?? this.flipX,
      flipY: flipY ?? this.flipY,
      zIndex: zIndex ?? this.zIndex,
      effects: effects ?? this.effects,
    );
  }

  factory StickerItem.fromJson(Map<String, dynamic> json) {
    return StickerItem(
      id: json['id'] as String,
      packId: json['packId'] as String,
      assetId: json['assetId'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      scale: (json['scale'] as num?)?.toDouble() ?? 1,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      flipX: json['flipX'] as bool? ?? false,
      flipY: json['flipY'] as bool? ?? false,
      zIndex: json['zIndex'] as int? ?? 0,
      effects: StickerEffects.fromJson(
        json['effects'] as Map<String, dynamic>?,
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'packId': packId,
    'assetId': assetId,
    'x': x,
    'y': y,
    'scale': scale,
    'rotation': rotation,
    'flipX': flipX,
    'flipY': flipY,
    'zIndex': zIndex,
    'effects': effects.toJson(),
  };
}

class TextItem extends ProjectItem {
  const TextItem({
    required super.id,
    required this.text,
    required this.fontFamily,
    required this.color,
    required super.x,
    required super.y,
    required super.zIndex,
    super.scale = 1,
    super.rotation = 0,
  });

  final String text;
  final String fontFamily;
  final String color;

  TextItem copyWith({
    String? text,
    String? fontFamily,
    String? color,
    double? x,
    double? y,
    double? scale,
    double? rotation,
    int? zIndex,
  }) {
    return TextItem(
      id: id,
      text: text ?? this.text,
      fontFamily: fontFamily ?? this.fontFamily,
      color: color ?? this.color,
      x: x ?? this.x,
      y: y ?? this.y,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      zIndex: zIndex ?? this.zIndex,
    );
  }

  factory TextItem.fromJson(Map<String, dynamic> json) {
    return TextItem(
      id: json['id'] as String,
      text: json['text'] as String? ?? '텍스트',
      fontFamily: json['fontFamily'] as String? ?? 'MemomentKkukkukk',
      color: json['color'] as String? ?? 'hsl(340 82% 62%)',
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      scale: (json['scale'] as num?)?.toDouble() ?? 1,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      zIndex: json['zIndex'] as int? ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'text',
    'text': text,
    'fontFamily': fontFamily,
    'color': color,
    'x': x,
    'y': y,
    'scale': scale,
    'rotation': rotation,
    'zIndex': zIndex,
  };
}
