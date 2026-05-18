import Foundation

/// Error type reserved for future use by the public bridge surface. The SDK
/// itself currently propagates errors through the JS callback (`hasError:
/// true`) rather than throwing, but `PMError` is kept so we can introduce a
/// throwing API later without source-breaking changes.
enum PMError: Error, Sendable {
    /// A non-categorised error carrying a free-form reason.
    case dynamic(reason: String)

    /// The owning instance has been deallocated. Emitted from `weak self`
    /// async paths that observe `self == nil`.
    case gone
}
