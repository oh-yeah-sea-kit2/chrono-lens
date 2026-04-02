enum Era {
  passthrough(0x00, 'オリジナル', 'Original'),
  taisho(0x01, '大正時代', '1912–1926'),
  showaEarly(0x02, '昭和初期', '1926–1945'),
  showaMid(0x03, '昭和中期', '1945–1970'),
  meiji(0x04, '明治時代', '1868–1912');

  const Era(this.id, this.label, this.subtitle);

  final int id;
  final String label;
  final String subtitle;
}
