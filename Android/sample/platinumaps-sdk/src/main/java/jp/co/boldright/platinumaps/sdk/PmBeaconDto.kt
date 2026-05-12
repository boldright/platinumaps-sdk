package jp.co.boldright.platinumaps.sdk

import java.util.Date

/**
 * Internal representation of a single ranged iBeacon advertisement. Used as
 * the intermediate value between the BLE scan callback and the JS bridge.
 */
class PmBeaconDto(
    var uuid: String,
    var major: Int,
    var minor: Int,
    var rssi: Int,
    var timestamp: Date = Date()
) {

    override fun toString(): String {
        // UUID intentionally omitted from the debug string so it does not
        // leak into shared logs.
        return "Beacon{major=$major, minor=$minor, rssi=$rssi}"
    }
}
