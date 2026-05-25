package jp.co.boldright.platinumaps.flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [PlatinumapsPlatformView.buildMapOptions] and the
 * launch-URL scheme allowlist. Runs on the JVM via the AGP `test`
 * source set — no WebView, no Robolectric.
 */
class PlatinumapsPlatformViewTest {

    @Test
    fun `null args resolve to an empty mapPath and no extras`() {
        val options = PlatinumapsPlatformView.buildMapOptions(null)
        assertEquals("", options.mapPath)
        assertNull(options.queryParams)
        assertNull(options.beacon)
        assertEquals(0, options.safeAreaTop)
        assertEquals(0, options.safeAreaBottom)
    }

    @Test
    fun `mapSlug flows into mapPath verbatim`() {
        val options = PlatinumapsPlatformView.buildMapOptions(
            mapOf("mapSlug" to "demo/sr999"),
        )
        assertEquals("demo/sr999", options.mapPath)
    }

    @Test
    fun `queryParams are preserved when no locale is given`() {
        val options = PlatinumapsPlatformView.buildMapOptions(
            mapOf(
                "mapSlug" to "demo",
                "queryParams" to mapOf("key1" to "value1"),
            ),
        )
        assertEquals(mapOf("key1" to "value1"), options.queryParams)
    }

    @Test
    fun `locale folds into a culture query parameter`() {
        // The Dart API exposes `locale`; on Android we have no
        // first-class field for it, so the plugin glue maps it onto
        // the `culture` query string the web app understands.
        val options = PlatinumapsPlatformView.buildMapOptions(
            mapOf(
                "mapSlug" to "demo",
                "locale" to "zh-cn",
            ),
        )
        assertEquals(mapOf("culture" to "zh-cn"), options.queryParams)
    }

    @Test
    fun `locale merges into existing queryParams without clobbering them`() {
        val options = PlatinumapsPlatformView.buildMapOptions(
            mapOf(
                "mapSlug" to "demo",
                "queryParams" to mapOf("key1" to "value1"),
                "locale" to "ja",
            ),
        )
        assertEquals(
            mapOf("key1" to "value1", "culture" to "ja"),
            options.queryParams,
        )
    }

    @Test
    fun `beacon options round-trip fully when all fields are set`() {
        val options = PlatinumapsPlatformView.buildMapOptions(
            mapOf(
                "mapSlug" to "demo",
                "beacon" to mapOf(
                    "uuid" to "01234567-89AB-CDEF-0123-456789ABCDEF",
                    "minSample" to 4,
                    "maxHistory" to 32,
                    "memo" to "demo-zone",
                ),
            ),
        )
        val beacon = options.beacon
        assertEquals("01234567-89AB-CDEF-0123-456789ABCDEF", beacon?.uuid)
        assertEquals(4, beacon?.minSample)
        assertEquals(32, beacon?.maxHistory)
        assertEquals("demo-zone", beacon?.memo)
    }

    @Test
    fun `beacon options accept Long-typed numbers from the platform channel`() {
        // The standard message codec deserializes integers as Long on
        // Android; the parser should coerce them down to Int rather
        // than throwing.
        val options = PlatinumapsPlatformView.buildMapOptions(
            mapOf(
                "mapSlug" to "demo",
                "beacon" to mapOf(
                    "uuid" to "01234567-89AB-CDEF-0123-456789ABCDEF",
                    "minSample" to 4L,
                    "maxHistory" to 32L,
                ),
            ),
        )
        val beacon = options.beacon
        assertEquals(4, beacon?.minSample)
        assertEquals(32, beacon?.maxHistory)
        assertNull(beacon?.memo)
    }

    @Test
    fun `userId and secretKey flow into PmMapOptions`() {
        val options = PlatinumapsPlatformView.buildMapOptions(
            mapOf(
                "mapSlug" to "demo",
                "userId" to "u-1",
                "secretKey" to "s-1",
            ),
        )
        assertEquals("u-1", options.userId)
        assertEquals("s-1", options.secretKey)
    }

    @Test
    fun `appStoreId and launchUrl are not echoed into PmMapOptions`() {
        // These keys are consumed elsewhere (iOS-only or by the init
        // block); the parser should not invent fields for them.
        val options = PlatinumapsPlatformView.buildMapOptions(
            mapOf(
                "mapSlug" to "demo",
                "appStoreId" to "1234567890",
                "launchUrl" to "https://platinumaps.jp/maps/demo",
            ),
        )
        assertEquals("demo", options.mapPath)
        assertNull(options.queryParams)
        assertNull(options.beacon)
        assertNull(options.userId)
        assertNull(options.secretKey)
    }

    @Test
    fun `safeAreaTop and safeAreaBottom flow into PmMapOptions verbatim`() {
        val options = PlatinumapsPlatformView.buildMapOptions(
            mapOf(
                "mapSlug" to "demo",
                "safeAreaTop" to 48,
                "safeAreaBottom" to 16,
            ),
        )
        assertEquals(48, options.safeAreaTop)
        assertEquals(16, options.safeAreaBottom)
    }

    @Test
    fun `safe-area defaults to zero when the Dart side omits the keys`() {
        val options = PlatinumapsPlatformView.buildMapOptions(
            mapOf("mapSlug" to "demo"),
        )
        assertEquals(0, options.safeAreaTop)
        assertEquals(0, options.safeAreaBottom)
    }

    @Test
    fun `isAllowedLaunchUrlScheme accepts every scheme in the SDK allowlist`() {
        for (scheme in listOf("http", "https", "tel", "mailto", "sms", "geo")) {
            assertTrue(
                "expected $scheme to be allowed",
                PlatinumapsPlatformView.isAllowedLaunchUrlScheme(scheme),
            )
        }
    }

    @Test
    fun `isAllowedLaunchUrlScheme is case-insensitive`() {
        assertTrue(PlatinumapsPlatformView.isAllowedLaunchUrlScheme("HTTPS"))
        assertTrue(PlatinumapsPlatformView.isAllowedLaunchUrlScheme("Mailto"))
    }

    @Test
    fun `isAllowedLaunchUrlScheme rejects unsafe schemes`() {
        for (scheme in listOf("javascript", "file", "intent", "about", "data")) {
            assertFalse(
                "expected $scheme to be rejected",
                PlatinumapsPlatformView.isAllowedLaunchUrlScheme(scheme),
            )
        }
    }

    @Test
    fun `isAllowedLaunchUrlScheme rejects null and empty`() {
        assertFalse(PlatinumapsPlatformView.isAllowedLaunchUrlScheme(null))
        assertFalse(PlatinumapsPlatformView.isAllowedLaunchUrlScheme(""))
    }
}
