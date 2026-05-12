package jp.co.boldright.platinumaps.sdk

/**
 * Three-valued authorization state reported to the web layer over the
 * `command://` bridge. Android's runtime-permission model has more shades
 * than this (granted / soft-denied / hard-denied "Don't ask again"), and
 * the SDK collapses them: a hard-deny is reported as `NOT_DETERMINED`
 * because, from the user's point of view, only Settings can unstick it.
 */
enum class PmAuthorizationStatus(val rawValue: String) {
    NOT_DETERMINED("notDetermined"),
    AUTHORIZED("authorized"),
    DENIED("denied"),
}
