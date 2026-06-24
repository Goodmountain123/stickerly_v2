class StickerEffects {
  const StickerEffects({
    this.floorShadow = const FloorShadowEffect(),
    this.blur = const IntensityEffect(),
    this.brightness = const IntensityEffect(intensity: 0.25),
    this.outglow = const GlowEffect(),
  });

  final FloorShadowEffect floorShadow;
  final IntensityEffect blur;
  final IntensityEffect brightness;
  final GlowEffect outglow;

  StickerEffects copyWith({
    FloorShadowEffect? floorShadow,
    IntensityEffect? blur,
    IntensityEffect? brightness,
    GlowEffect? outglow,
  }) {
    return StickerEffects(
      floorShadow: floorShadow ?? this.floorShadow,
      blur: blur ?? this.blur,
      brightness: brightness ?? this.brightness,
      outglow: outglow ?? this.outglow,
    );
  }

  factory StickerEffects.fromJson(Map<String, dynamic>? json) {
    final source = json ?? const <String, dynamic>{};
    return StickerEffects(
      floorShadow: FloorShadowEffect.fromJson(
        source['floorShadow'] as Map<String, dynamic>?,
      ),
      blur: IntensityEffect.fromJson(source['blur'] as Map<String, dynamic>?),
      brightness: IntensityEffect.fromJson(
        source['brightness'] as Map<String, dynamic>?,
        defaultIntensity: 0.25,
      ),
      outglow: GlowEffect.fromJson(source['outglow'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toJson() => {
    'floorShadow': floorShadow.toJson(),
    'blur': blur.toJson(),
    'brightness': brightness.toJson(),
    'outglow': outglow.toJson(),
  };
}

class IntensityEffect {
  const IntensityEffect({this.enabled = false, this.intensity = 0.5});

  final bool enabled;
  final double intensity;

  IntensityEffect copyWith({bool? enabled, double? intensity}) {
    return IntensityEffect(
      enabled: enabled ?? this.enabled,
      intensity: intensity ?? this.intensity,
    );
  }

  factory IntensityEffect.fromJson(
    Map<String, dynamic>? json, {
    double defaultIntensity = 0.5,
  }) {
    return IntensityEffect(
      enabled: json?['enabled'] as bool? ?? false,
      intensity: (json?['intensity'] as num?)?.toDouble() ?? defaultIntensity,
    );
  }

  Map<String, dynamic> toJson() => {'enabled': enabled, 'intensity': intensity};
}

class FloorShadowEffect extends IntensityEffect {
  const FloorShadowEffect({
    super.enabled,
    super.intensity,
    this.blur = 0.5,
    this.x = 0,
    this.y = 0,
    this.scale = 1,
  });

  final double blur;
  final double x;
  final double y;
  final double scale;

  @override
  FloorShadowEffect copyWith({
    bool? enabled,
    double? intensity,
    double? blur,
    double? x,
    double? y,
    double? scale,
  }) {
    return FloorShadowEffect(
      enabled: enabled ?? this.enabled,
      intensity: intensity ?? this.intensity,
      blur: blur ?? this.blur,
      x: x ?? this.x,
      y: y ?? this.y,
      scale: scale ?? this.scale,
    );
  }

  factory FloorShadowEffect.fromJson(Map<String, dynamic>? json) {
    return FloorShadowEffect(
      enabled: json?['enabled'] as bool? ?? false,
      intensity: (json?['intensity'] as num?)?.toDouble() ?? 0.5,
      blur: (json?['blur'] as num?)?.toDouble() ?? 0.5,
      x: (json?['x'] as num?)?.toDouble() ?? 0,
      y: (json?['y'] as num?)?.toDouble() ?? 0,
      scale: (json?['scale'] as num?)?.toDouble() ?? 1,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'blur': blur,
    'x': x,
    'y': y,
    'scale': scale,
  };
}

class GlowEffect extends IntensityEffect {
  const GlowEffect({
    super.enabled,
    super.intensity,
    this.color = 'hsl(205 100% 74%)',
  });

  final String color;

  @override
  GlowEffect copyWith({bool? enabled, double? intensity, String? color}) {
    return GlowEffect(
      enabled: enabled ?? this.enabled,
      intensity: intensity ?? this.intensity,
      color: color ?? this.color,
    );
  }

  factory GlowEffect.fromJson(Map<String, dynamic>? json) {
    return GlowEffect(
      enabled: json?['enabled'] as bool? ?? false,
      intensity: (json?['intensity'] as num?)?.toDouble() ?? 0.5,
      color: json?['color'] as String? ?? 'hsl(205 100% 74%)',
    );
  }

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'color': color};
}
