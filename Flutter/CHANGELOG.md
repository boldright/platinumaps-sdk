# Changelog

All notable changes to this package are documented in this file. The
format follows [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

### Added

- Initial scaffold for the Platinumaps Flutter SDK. Public Dart API
  surface (`PlatinumapsMapView`, `PlatinumapsBeaconOptions`,
  `PlatinumapsLocale`) is in place. Native plugin glue wraps the
  existing iOS / Android SDKs via PlatformView. See `DESIGN.md`.
