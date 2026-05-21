#
# CocoaPods spec for the Platinumaps Flutter plugin.
#
# For in-repo development, this podspec vendors the existing iOS SDK
# source files from `iOS/platinumaps-sdk/` (two directories up) via a
# relative glob. The publish workflow (`scripts/prepublish.py`)
# materializes those sources into the snapshot before uploading to
# pub.dev so the relative path is no longer needed at install time.
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
    '../../../iOS/platinumaps-sdk/**/*.swift',
  ]
  s.dependency 'Flutter'
  s.platform = :ios, '16.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_VERSION' => '6.0',
  }
end
