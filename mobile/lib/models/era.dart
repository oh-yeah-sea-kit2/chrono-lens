enum Era {
  passthrough(0x00, 'オリジナル', 'Original', null),
  taisho(0x01, '大正時代', '1912–1926', 'assets/styles/taisho.jpg'),
  showaEarly(0x02, '昭和初期', '1926–1945', 'assets/styles/showa_early.jpg'),
  showaMid(0x03, '昭和中期', '1945–1970', 'assets/styles/showa_mid.jpg'),
  meiji(0x04, '明治時代', '1868–1912', 'assets/styles/meiji.jpg');

  const Era(this.id, this.label, this.subtitle, this.styleAsset);

  final int id;
  final String label;
  final String subtitle;

  /// Path to the style reference image asset. Null for passthrough.
  final String? styleAsset;
}
