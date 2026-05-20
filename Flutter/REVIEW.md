# Code Review Follow-up (in progress)

Tracking the 50 findings from the local-environment review pass.

Status legend: ⬜ todo / 🟡 in progress / ✅ done / ❌ won't fix.

## Required (#1–#7)

- ⬜ **#1** Android: Activity の pause/resume が plugin に届かず、background でも GPS / BLE スキャン継続 — `Flutter/platinumaps_flutter_sdk/android/src/main/kotlin/jp/co/boldright/platinumaps/flutter/PlatinumapsPlatformView.kt:94`
  - `onFlutterViewAttached/Detached` は PlatformView の attach/detach で発火し、Activity の onPause/onResume では発火しない。`ActivityAware` から取った binding に `LifecycleEventObserver` を仕掛けて `activityPause/Resume` を Activity ライフサイクルに駆動させる必要あり。
- ⬜ **#2** Android: result listener が常に true を返し、他プラグインの permission/activity result を奪う — `Flutter/platinumaps_flutter_sdk/android/src/main/kotlin/jp/co/boldright/platinumaps/flutter/PlatinumapsFlutterPlugin.kt:28`
  - `forwardPermissionResult` / `forwardActivityResult` 経路で「自分の要求コードに合致するか」判定して、合致時のみ true。
- ⬜ **#3** iOS: mapSlug='' (Dart 的に valid) でも fatalError 即死 — `iOS/platinumaps-sdk/Views/PMMapView.swift:290`
  - 空文字を warn + early return に格下げ、もしくは Dart API 側で空文字を弾く。
- ⬜ **#4** iOS: Flutter plugin が delegate を常時セットし、Dart 側 onOpenLink=null の時にリンクが silent drop（ネイティブ既定の SFSafariViewController も発動しない） — `Flutter/platinumaps_flutter_sdk/ios/platinumaps_flutter_sdk/Sources/platinumaps_flutter_sdk/PlatinumapsPlatformView.swift:27`
  - Dart の `onOpenLink` 設定有無を creation args で送り、未設定なら delegate を立てない。`#23` と一括対応。
- ⬜ **#5** iOS: PMLocalizedStrings の言語解決が `Bundle.main.preferredLocalizations` に依存。Flutter host の Info.plist に `CFBundleLocalizations` 未宣言だと日本語デバイスでも英語に flat — `iOS/platinumaps-sdk/Types/PMLocalizedStrings.swift:11`
  - `Locale.current.languageCode` (or `Locale.preferredLanguages.first`) を先に使う方針へ。
- ⬜ **#6** coverImage の Dart doc / README は「iOS で表示される」と書くが実装は両プラットフォーム未配線 — `Flutter/platinumaps_flutter_sdk/lib/src/platinumaps_map_view.dart:84`
  - v0.1 は doc を「未配線、§8 #5 で再評価」へ訂正。`#21` と一括。
- ⬜ **#7** CLAUDE.md の lifecycle / threading / "Where to make common changes" 記述が PMMapView リファクタを反映していない — `CLAUDE.md:128`

## Recommended (#8–#50)

- ⬜ **#8** iOS: WKUIDelegate alert/confirm panel で `presentationViewController == nil` 時に completionHandler 未呼出 → WebView hang — `iOS/platinumaps-sdk/Views/PMMapView.swift:475`
- ⬜ **#9** iOS: beacon の minSample/maxHistory/memo が無視される (Android は URL query で送る、不整合) — `Flutter/platinumaps_flutter_sdk/ios/platinumaps_flutter_sdk/Sources/platinumaps_flutter_sdk/PlatinumapsPlatformView.swift:66`
- ⬜ **#10** iOS: locale と queryParams 両方指定で URL に `culture=` 重複 — `iOS/platinumaps-sdk/Views/PMMapView.swift:339`
- ⬜ **#11** Flutter example の Android main/AndroidManifest.xml に `INTERNET` 欠落 (release ビルドで WebView が動かない) — `Flutter/example/android/app/src/main/AndroidManifest.xml:1`
- ⬜ **#12** example の `path: ../platinumaps_flutter_sdk` は published 時に example が同梱されると壊れる — `Flutter/example/pubspec.yaml:39`
- ⬜ **#13** iOS PMMapView.swift に typo "fucn" — `iOS/platinumaps-sdk/Views/PMMapView.swift:1320`
- ⬜ **#14** iOS plugin PlatinumapsPlatformView クラスに `@MainActor` 注釈なし — `Flutter/platinumaps_flutter_sdk/ios/platinumaps_flutter_sdk/Sources/platinumaps_flutter_sdk/PlatinumapsPlatformView.swift:7`
- ⬜ **#15** iOS plugin: deinit で mapView.delegate = nil していない (Android との対称性 / 安全性) — `Flutter/platinumaps_flutter_sdk/ios/platinumaps_flutter_sdk/Sources/platinumaps_flutter_sdk/PlatinumapsPlatformView.swift:7`
- ⬜ **#16** Dart `_handleMethodCall` で `call.arguments as Map` の防御不足 + raw type — `Flutter/platinumaps_flutter_sdk/lib/src/platinumaps_map_view.dart:148`
- ⬜ **#17** example の `_handleOpenLink` が `Future<void>` を返しエラーが捨てられる — `Flutter/example/lib/main.dart:32`
- ⬜ **#18** 複数 PlatinumapsMapView 同時表示で permission/file chooser のルーティング衝突 — `Flutter/platinumaps_flutter_sdk/android/src/main/kotlin/jp/co/boldright/platinumaps/flutter/PlatinumapsPlatformViewFactory.kt:38`
- ⬜ **#19** Android plugin: queryParams の unchecked cast が型不一致でクラッシュリスク — `Flutter/platinumaps_flutter_sdk/android/src/main/kotlin/jp/co/boldright/platinumaps/flutter/PlatinumapsPlatformView.kt:62`
- ⬜ **#20** Android plugin: factory が `activity == null` を fallback context にし、permission request が無音失敗 — `Flutter/platinumaps_flutter_sdk/android/src/main/kotlin/jp/co/boldright/platinumaps/flutter/PlatinumapsPlatformViewFactory.kt:24`
- ⬜ **#21** Flutter README の Configuration テーブルで coverImage を iOS ✓ と記載 (#6 と関連) — `Flutter/platinumaps_flutter_sdk/README.md:115`
- ⬜ **#22** Flutter README の "Sample app: (to be added)" が陳腐化 — `Flutter/platinumaps_flutter_sdk/README.md:144`
- ⬜ **#23** Flutter README / dartdoc が「onOpenLink=null でネイティブ既定にフォールバック」と書くが iOS は #4、Android は `browse.app` のみフォールバック — `Flutter/platinumaps_flutter_sdk/lib/src/platinumaps_map_view.dart:102`
- ⬜ **#24** iOS XCTest `test_malformedLaunchUrlIsIgnored` のコメントが事実と逆ではないか（iOS 17+ では nil を返すが、念のため OS バージョン依存性を明示） — `Flutter/example/ios/RunnerTests/RunnerTests.swift:128`
- ⬜ **#25** iOS Plugin の SwiftPM library 名がハイフン (`platinumaps-flutter-sdk`) — `Flutter/platinumaps_flutter_sdk/ios/platinumaps_flutter_sdk/Package.swift:42`
- ⬜ **#26** iOS PMMapView の `presentationViewController` 拡張と `pushLaunchURL` の responder walk が重複 — `iOS/platinumaps-sdk/Views/PMMapView.swift:457`
- ⬜ **#27** example アプリの DESIGN §7 全 public API デモ要件 (beacon, etc.) 未達 — `Flutter/example/lib/main.dart:46`
- ⬜ **#28** prepublish.py docstring のデフォルト出力先パス (`build/publish-snapshot/...`) が古い (実際は `/tmp/`) — `scripts/prepublish.py:25`
- ⬜ **#29** prepublish.py の Gradle/podspec の `_NEEDLE` 完全一致前提が脆い — `scripts/prepublish.py:136`
- ⬜ **#30** prepublish.py の materialize_symlinks がファイル symlink 非対応・loop guard なし — `scripts/prepublish.py:118`
- ⬜ **#31** iOS PMMapView deinit が non-main で呼ばれると `MainActor.assumeIsolated` がクラッシュ可能性 — `iOS/platinumaps-sdk/Views/PMMapView.swift:377`
- ⬜ **#32** iOS Plugin Factory の `MainActor.assumeIsolated` が non-main 呼び出しでトラップ — `Flutter/platinumaps_flutter_sdk/ios/platinumaps_flutter_sdk/Sources/platinumaps_flutter_sdk/PlatinumapsPlatformViewFactory.swift:15`
- ⬜ **#33** iOS PMMapView の公開 var が performFirstAttachSetup 後変更不可だが doc が不明示 — `iOS/platinumaps-sdk/Views/PMMapView.swift:84`
- ⬜ **#34** iOS plugin の applyCreationArguments の coverImage コメントが「opaque ImageProvider が wire 化されてない」前提だが、Dart 側は実は coverImage を送っていない (#6) — `Flutter/platinumaps_flutter_sdk/ios/platinumaps_flutter_sdk/Sources/platinumaps_flutter_sdk/PlatinumapsPlatformView.swift:31`
- ⬜ **#35** iOS WebView の `didFinish` で `hasInitialLoadFailed` ラッチがクリアされない (pre-existing) — `iOS/platinumaps-sdk/Views/PMMapView.swift:534`
- ⬜ **#36** iOS Podspec の `s.license` の相対パスが podspec 位置から1段上を指す。動作はするが慣例的でない — `Flutter/platinumaps_flutter_sdk/ios/platinumaps_flutter_sdk.podspec:22`
- ⬜ **#37** Android plugin AndroidManifest が空。SDK が要求する permission を `<uses-permission>` で宣言しないと manifest merger が機能しない — `Flutter/platinumaps_flutter_sdk/android/src/main/AndroidManifest.xml:1`
- ⬜ **#38** iOS README の PMMainViewControllerDelegate 説明 (typealias なのに独立 protocol のように記述) — `iOS/README.md:134`
- ⬜ **#39** iOS README の retry 否定文 ("It does not retry network failures itself") が古い — `iOS/README.md:178`
- ⬜ **#40** CLAUDE.md の app.info Command catalogue で offsetBottom の表記が混乱気味 — `CLAUDE.md:111`
- ⬜ **#41** example pubspec の Dart SDK constraint (`^3.12.0`) と plugin (`^3.4.0`) が乖離 — `Flutter/example/pubspec.yaml:22`
- ⬜ **#42** flutter_lints バージョン乖離 (plugin `^4.0.0`, example `^6.0.0`) — `Flutter/platinumaps_flutter_sdk/pubspec.yaml:19`
- ⬜ **#43** CHANGELOG: `[0.1.0]` リンク先タグが未公開、`[0.1.0] - Unreleased` 書式も不慣例 — `Flutter/platinumaps_flutter_sdk/CHANGELOG.md:66`
- ⬜ **#44** CHANGELOG: 「ten cases」と数字を直書きしているのが脆い — `Flutter/platinumaps_flutter_sdk/CHANGELOG.md:59`
- ⬜ **#45** DESIGN §9 step 2 が 🟡 のままだが CI でビルド検証は済んでいる — `Flutter/DESIGN.md:642`
- ⬜ **#46** pubspec.yaml に topics フィールドが無い (pana スコア向上余地) — `Flutter/platinumaps_flutter_sdk/pubspec.yaml:1`
- ⬜ **#47** example の iOS Info.plist に `NSLocationAlwaysAndWhenInUseUsageDescription` 無し — `Flutter/example/ios/Runner/Info.plist:1`
- ⬜ **#48** CI flutter-sdk-ci.yml に `flutter build apk --release` (proguard) 経路が無い — `.github/workflows/flutter-sdk-ci.yml:1`
- ⬜ **#49** launchUrl の Dart 文字列が iOS で `URL(string:)` を通すだけで `javascript:` 等もそのまま web へ送られる — `Flutter/platinumaps_flutter_sdk/ios/platinumaps_flutter_sdk/Sources/platinumaps_flutter_sdk/PlatinumapsPlatformView.swift:70`
- ⬜ **#50** i18n/strings.yaml に SDK Kotlin コードから参照されない未使用エントリ複数 (alert_settings/cancel/ok/yes/no/login, button_text_cancel, splash_image_description, qr_code_reader_message, dialog_*_camera_permission) — `i18n/strings.yaml:88`
