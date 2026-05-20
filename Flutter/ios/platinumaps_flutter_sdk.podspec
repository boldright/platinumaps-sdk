#
# CocoaPods spec for the Platinumaps Flutter plugin.
#
# For in-repo development, this podspec vendors the existing iOS SDK
# source files from `iOS/platinumaps-sdk/` (two directories up) via a
# relative glob. That arrangement works only when the plugin is
# consumed from a checkout of the full repository (e.g. `dependencies:
# platinumaps_flutter_sdk: { git: ... , path: Flutter }` in the host
# app's pubspec.yaml). It does NOT survive `dart pub publish` — only
# the `Flutter/` subtree is uploaded, and the relative path breaks.
# The publish-time packaging decision is tracked as `Flutter/DESIGN.md`
# §8 question #4.
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
  # same Swift sources. CocoaPods compiles them as one module, so the
  # `import PlatinumapsSDK` lines inside the plugin glue are gated on
  # `SWIFT_PACKAGE` and elide here.
  s.source_files     = [
    'platinumaps_flutter_sdk/Sources/platinumaps_flutter_sdk/**/*.swift',
    '../../iOS/platinumaps-sdk/**/*.swift',
  ]

  # The native SDK accesses its localized strings via
  # `Bundle.main.path(forResource: "Platinumaps", ofType: "bundle")`,
  # which requires the bundle to land in the consuming app's main
  # bundle rather than under a namespaced resource_bundles directory
  # inside the plugin framework. `s.resources` keeps that behaviour.
  s.resources        = ['../../iOS/platinumaps-sdk/Platinumaps.bundle']
  s.dependency 'Flutter'
  s.platform = :ios, '16.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_VERSION' => '6.0',
  }
end
