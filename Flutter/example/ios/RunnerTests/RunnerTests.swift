import Flutter
import UIKit
import XCTest
@testable import platinumaps_flutter_sdk

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

}

/// Unit tests for `PlatinumapsPlatformView.applyCreationArguments(_:to:)`.
/// Lives in the example app's test target because that's the only
/// place where the Flutter plugin's symbols and a full UIKit runtime
/// are both available at test time.
@MainActor
final class PlatinumapsPlatformViewTests: XCTestCase {

    func test_nilArguments_leaveTheMapViewAtItsDefaults() throws {
        let mapView = PMMapView(frame: .zero)
        PlatinumapsPlatformView.applyCreationArguments(nil, to: mapView)

        XCTAssertNil(mapView.mapSlug)
        XCTAssertEqual(mapView.mapQuery, [:])
        XCTAssertNil(mapView.mapLocale)
        XCTAssertNil(mapView.appStoreId)
        XCTAssertNil(mapView.userId)
        XCTAssertNil(mapView.secretKey)
        XCTAssertEqual(mapView.offsetBottom, 0)
        XCTAssertNil(mapView.beaconUuid)
        XCTAssertNil(mapView.launchURL)
    }

    func test_mapSlugAndQueryParamsAreApplied() throws {
        let mapView = PMMapView(frame: .zero)
        PlatinumapsPlatformView.applyCreationArguments(
            [
                "mapSlug": "demo/sr999",
                "queryParams": ["key1": "value1"],
            ],
            to: mapView
        )

        XCTAssertEqual(mapView.mapSlug, "demo/sr999")
        XCTAssertEqual(mapView.mapQuery, ["key1": "value1"])
    }

    func test_localeStringIsTranslatedToPMLocale() throws {
        let mapView = PMMapView(frame: .zero)
        PlatinumapsPlatformView.applyCreationArguments(
            ["mapSlug": "demo", "locale": "zh-cn"],
            to: mapView
        )

        XCTAssertEqual(mapView.mapLocale, .zhHans)
    }

    func test_unknownLocaleStringIsIgnoredRatherThanCrashing() throws {
        // The Dart enum is exhaustive, but a misbehaving caller could
        // send an unknown string through the platform channel. Reject
        // it silently instead of crashing the host app.
        let mapView = PMMapView(frame: .zero)
        PlatinumapsPlatformView.applyCreationArguments(
            ["mapSlug": "demo", "locale": "klingon"],
            to: mapView
        )

        XCTAssertNil(mapView.mapLocale)
    }

    func test_appInfoFieldsAreApplied() throws {
        let mapView = PMMapView(frame: .zero)
        PlatinumapsPlatformView.applyCreationArguments(
            [
                "mapSlug": "demo",
                "appStoreId": "1234567890",
                "userId": "u-1",
                "secretKey": "s-1",
                "offsetBottom": 24,
            ],
            to: mapView
        )

        XCTAssertEqual(mapView.appStoreId, "1234567890")
        XCTAssertEqual(mapView.userId, "u-1")
        XCTAssertEqual(mapView.secretKey, "s-1")
        XCTAssertEqual(mapView.offsetBottom, 24)
    }

    func test_beaconUuidIsApplied() throws {
        let mapView = PMMapView(frame: .zero)
        PlatinumapsPlatformView.applyCreationArguments(
            [
                "mapSlug": "demo",
                "beacon": [
                    "uuid": "01234567-89AB-CDEF-0123-456789ABCDEF",
                    "minSample": 4,
                ],
            ],
            to: mapView
        )

        XCTAssertEqual(
            mapView.beaconUuid,
            "01234567-89AB-CDEF-0123-456789ABCDEF"
        )
    }

    func test_beaconExtrasAreFoldedIntoMapQuery() throws {
        // The native iOS SDK has no first-class API for the optional
        // beacon-tuning fields, so the plugin folds them into the
        // URL query parameter shape the native Android SDK already
        // uses (`beaconminsample`, `beaconmaxhistory`, `memo`).
        let mapView = PMMapView(frame: .zero)
        PlatinumapsPlatformView.applyCreationArguments(
            [
                "mapSlug": "demo",
                "beacon": [
                    "uuid": "01234567-89AB-CDEF-0123-456789ABCDEF",
                    "minSample": 4,
                    "maxHistory": 32,
                    "memo": "demo-zone",
                ],
            ],
            to: mapView
        )

        XCTAssertEqual(mapView.mapQuery["beaconminsample"], "4")
        XCTAssertEqual(mapView.mapQuery["beaconmaxhistory"], "32")
        XCTAssertEqual(mapView.mapQuery["memo"], "demo-zone")
    }

    func test_launchUrlIsParsedAndAppliedWhenValid() throws {
        let mapView = PMMapView(frame: .zero)
        PlatinumapsPlatformView.applyCreationArguments(
            [
                "mapSlug": "demo",
                "launchUrl": "https://platinumaps.jp/maps/demo/sr999",
            ],
            to: mapView
        )

        XCTAssertEqual(
            mapView.launchURL,
            URL(string: "https://platinumaps.jp/maps/demo/sr999")
        )
    }

    func test_malformedLaunchUrlIsIgnored() throws {
        // URL(string:) succeeds for almost any input, but an empty
        // string returns nil. Use that to verify the parser doesn't
        // assign nil-typed garbage to launchURL.
        let mapView = PMMapView(frame: .zero)
        PlatinumapsPlatformView.applyCreationArguments(
            [
                "mapSlug": "demo",
                "launchUrl": "",
            ],
            to: mapView
        )

        XCTAssertNil(mapView.launchURL)
    }

    func test_launchUrlIsRejectedWhenSchemeIsNotAllowed() throws {
        // The plugin mirrors the SDK's browseAllowedSchemes allowlist
        // (http, https, tel, mailto, sms, geo) on the inbound
        // launchUrl path so a host cannot smuggle a `javascript:`
        // URL into the embedded WebView.
        let mapView = PMMapView(frame: .zero)
        PlatinumapsPlatformView.applyCreationArguments(
            [
                "mapSlug": "demo",
                "launchUrl": "javascript:alert('x')",
            ],
            to: mapView
        )

        XCTAssertNil(mapView.launchURL)
    }

    // MARK: - pushLaunchUrl scheme allowlist

    func test_isAllowedLaunchUrlScheme_acceptsEverySchemeInTheAllowlist() throws {
        let allowedUrls = [
            URL(string: "https://example.com")!,
            URL(string: "http://example.com")!,
            URL(string: "tel:1234")!,
            URL(string: "mailto:foo@example.com")!,
            URL(string: "sms:1234")!,
            URL(string: "geo:0,0")!,
        ]
        for url in allowedUrls {
            XCTAssertTrue(
                PlatinumapsPlatformView.isAllowedLaunchUrlScheme(url),
                "expected \(url) to be allowed"
            )
        }
    }

    func test_isAllowedLaunchUrlScheme_isCaseInsensitive() throws {
        XCTAssertTrue(
            PlatinumapsPlatformView.isAllowedLaunchUrlScheme(
                URL(string: "HTTPS://example.com")!
            )
        )
    }

    func test_isAllowedLaunchUrlScheme_rejectsUnsafeSchemes() throws {
        let rejectedUrls = [
            URL(string: "javascript:alert('x')")!,
            URL(string: "file:///etc/passwd")!,
            URL(string: "data:text/html,<h1>x</h1>")!,
        ]
        for url in rejectedUrls {
            XCTAssertFalse(
                PlatinumapsPlatformView.isAllowedLaunchUrlScheme(url),
                "expected \(url) to be rejected"
            )
        }
    }
}
