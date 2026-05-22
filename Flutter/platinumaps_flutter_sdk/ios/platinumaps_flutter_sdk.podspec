#
# CocoaPods spec for the Platinumaps Flutter plugin.
#
# `Sources/PlatinumapsSDK/` is a byte-identical mirror of
# `iOS/platinumaps-sdk/`. Both the SwiftPM build
# (`platinumaps_flutter_sdk/Package.swift`) and this CocoaPods
# podspec compile that in-package directory. The mirror exists
# because CocoaPods cannot follow a symlink into the canonical
# tree and a relative `../../../iOS/platinumaps-sdk/**/*.swift`
# glob also fails: Flutter installs every plugin under
# `ios/.symlinks/plugins/<plugin>/` and resolves the glob
# logically from that location, so the relative path ends up
# pointing at a non-existent `ios/.symlinks/iOS/platinumaps-sdk/`.
# Keeping all sources inside the podspec directory sidesteps
# both problems. The CI `mirror-sync` job enforces the
# byte-identity (`diff -r iOS/platinumaps-sdk Flutter/.../Sources/PlatinumapsSDK`).
#
Pod::Spec.new do |s|
  s.name             = 'platinumaps_flutter_sdk'
  s.version          = '0.1.0'
  s.summary          = 'Flutter SDK for embedding the Platinumaps web map.'
  s.description      = <<-DESC
Flutter SDK for embedding the Platinumaps web map in a Flutter app.
                       DESC
  s.homepage         = 'https://github.com/boldright/platinumaps-sdk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Bold Right Inc.' => '' }
  s.source           = { :path => '.' }
  # Both the CocoaPods build (single module: this podspec) and the
  # SwiftPM build (`platinumaps_flutter_sdk/Package.swift`) read the
  # same Swift sources. Localized permission-alert strings are
  # embedded in `PMLocalizedStrings.swift` so neither build ships a
  # resource bundle.
  s.source_files     = [
    'platinumaps_flutter_sdk/Sources/platinumaps_flutter_sdk/**/*.swift',
    'platinumaps_flutter_sdk/Sources/PlatinumapsSDK/**/*.swift',
  ]
  s.dependency 'Flutter'
  s.platform = :ios, '16.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # The plugin glue uses `MainActor.assumeIsolated { ... }` with
    # captures (`Any?`, `FlutterBinaryMessenger`) that are not
    # `Sendable`. Swift 6's default strict-concurrency check rejects
    # these captures. Compile under Swift 5 language mode here — the
    # SwiftPM build path (Flutter 3.44+) does not run strict-
    # concurrency check by default either, so behaviour stays
    # consistent across CocoaPods and SwiftPM consumption. Swift 6
    # language mode adoption (with `Sendable` annotations on the
    # Flutter-side types) is tracked separately.
    'SWIFT_VERSION' => '5.0',
  }
end
