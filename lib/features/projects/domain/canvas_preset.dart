enum CanvasPreset {
  square(width: 1080, height: 1080, ratio: '1 : 1', label: '정사각형'),
  portrait45(width: 1080, height: 1350, ratio: '4 : 5', label: '세로형'),
  portrait34(width: 1080, height: 1440, ratio: '3 : 4', label: '세로형'),
  story(width: 1080, height: 1920, ratio: '9 : 16', label: '스토리'),
  landscape169(width: 1920, height: 1080, ratio: '16 : 9', label: '와이드'),
  landscape43(width: 1440, height: 1080, ratio: '4 : 3', label: '가로형');

  const CanvasPreset({
    required this.width,
    required this.height,
    required this.ratio,
    required this.label,
  });

  final int width;
  final int height;
  final String ratio;
  final String label;

  static CanvasPreset fromJson(String? value) {
    final normalized = switch (value) {
      'phone' => 'story',
      'tablet' => 'portrait34',
      _ => value,
    };

    return CanvasPreset.values.firstWhere(
      (preset) => preset.name == normalized,
      orElse: () => CanvasPreset.square,
    );
  }
}
