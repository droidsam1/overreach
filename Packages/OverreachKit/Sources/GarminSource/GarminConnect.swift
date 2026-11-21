import Domain
import Foundation
import GarminImport

/// Builds the Garmin service the app uses (ADR-0022): the logic lives in `GarminImport` (OverreachCore, tested on
/// Linux); this module supplies the Keychain, URLSession and a cache file.
public enum GarminConnect {
    /// The account (connect, sync, disconnect) and the metrics source are the same object.
    public static func makeService() -> any GarminAccount & MetricsSource & ActivitySource & RecordedStrengthSource {
        GarminService(
            transport: URLSessionGarminTransport(),
            secrets: KeychainGarminSecrets(),
            cache: FileGarminCache()
        )
    }
}
