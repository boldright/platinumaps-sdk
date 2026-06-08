/// Languages supported by the Platinumaps web app.
///
/// The wire value (see [code]) is sent as the `culture` query parameter
/// the web app expects.
enum PlatinumapsLocale {
  /// Japanese.
  ja('ja'),

  /// English.
  en('en'),

  /// Simplified Chinese.
  zhHans('zh-cn'),

  /// Traditional Chinese.
  zhHant('zh-tw'),

  /// Korean.
  ko('ko'),

  /// French.
  fr('fr'),

  /// Spanish.
  es('es'),

  /// Vietnamese.
  vi('vi'),

  /// Indonesian.
  id('id'),

  /// Burmese.
  my('my'),

  /// Thai.
  th('th');

  const PlatinumapsLocale(this.code);

  /// The wire format sent to the web app and to the native side.
  final String code;
}
