/// 感情ラベルの定義（backend の allowedEmotions と一致させること）。
class EmotionOption {
  const EmotionOption(this.key, this.emoji, this.label);

  final String key;
  final String emoji;
  final String label;
}

/// 選択できる感情ラベル一覧。
const emotionOptions = <EmotionOption>[
  EmotionOption('calm', '😌', '落ち着く'),
  EmotionOption('happy', '😊', '楽しい'),
  EmotionOption('excited', '🤩', 'わくわく'),
  EmotionOption('nostalgic', '🥲', '懐かしい'),
  EmotionOption('moved', '🥹', '感動'),
];

/// key から感情定義を引く（未知・null は null）。
EmotionOption? emotionByKey(String? key) {
  if (key == null || key.isEmpty) return null;
  for (final e in emotionOptions) {
    if (e.key == key) return e;
  }
  return null;
}
