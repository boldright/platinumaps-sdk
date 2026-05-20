/// Beacon ranging configuration for [PlatinumapsMapView].
///
/// Mirrors the native SDK's `PmMapBeaconOptions` (Android) /
/// `beaconUuid` properties (iOS). The values are passed through to the
/// embedded web app and govern how the map reacts to incoming beacon
/// data. Once a [PlatinumapsMapView] has been constructed, the beacon
/// options are immutable for the lifetime of that view — rebuild the
/// widget with a new instance to change them.
class PlatinumapsBeaconOptions {
  /// Creates a beacon configuration.
  ///
  /// [uuid] is the proximity UUID (hyphenated) to listen for. The
  /// native SDK refuses to start scanning when the string fails to
  /// parse as a UUID, so beacons are silently disabled in that case.
  const PlatinumapsBeaconOptions({
    required this.uuid,
    this.minSample,
    this.maxHistory,
    this.memo,
  });

  /// Proximity UUID of the beacons to listen for.
  final String uuid;

  /// Optional. Number of RSSI samples the map should average before
  /// reacting; falls back to the map-side default when `null`.
  final int? minSample;

  /// Optional. Maximum history length the map should retain; falls
  /// back to the map-side default when `null`.
  final int? maxHistory;

  /// Optional free-form string forwarded to the map for diagnostic
  /// purposes.
  final String? memo;

  /// Wire form sent across the platform channel.
  Map<String, Object?> toMap() => {
        'uuid': uuid,
        if (minSample != null) 'minSample': minSample,
        if (maxHistory != null) 'maxHistory': maxHistory,
        if (memo != null) 'memo': memo,
      };
}
