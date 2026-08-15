import Foundation

/// Assembles the supported providers from their bundled specs
/// (`Resources/ProviderSpecs/<id>.json`, synced from `Contracts/Providers/` by
/// `scripts/sync-specs-to-core.sh`). A missing or invalid spec resource is a
/// packaging error, not a runtime state, so loading fails fast.
public enum ProviderCatalog {
    /// Validated specs for every known provider id, loaded once from the core
    /// bundle. Static initialization is lazy and thread-safe.
    private static let specs: [ProviderID: ProviderSpec] = {
        var specs: [ProviderID: ProviderSpec] = [:]
        for id in ProviderID.allCases {
            do {
                specs[id] = try ProviderSpecLoader.spec(for: id)
            } catch {
                fatalError(
                    "ProviderCatalog: bundled spec for '\(id.rawValue)' failed to load: \(error)"
                )
            }
        }
        return specs
    }()

    /// Descriptors derived from the specs, built once alongside them.
    private static let descriptors: [ProviderID: ProviderDescriptor] =
        specs.mapValues { spec in
            // The spec validated at load time, so construction cannot fail.
            try! SpecDrivenProvider(spec: spec).descriptor
        }

    /// One fresh provider instance per known id, in `ProviderID` declaration
    /// order. Every call builds new instances; callers must not share them
    /// across accounts.
    public static var all: [any UsageProvider] {
        ProviderID.allCases.map { id in
            // The spec validated at load time, so construction cannot fail.
            try! SpecDrivenProvider(spec: spec(for: id))
        }
    }

    public static func descriptor(for id: ProviderID) -> ProviderDescriptor {
        guard let descriptor = descriptors[id] else {
            fatalError("ProviderCatalog: no descriptor for '\(id.rawValue)'")
        }
        return descriptor
    }

    private static func spec(for id: ProviderID) -> ProviderSpec {
        guard let spec = specs[id] else {
            fatalError("ProviderCatalog: no bundled spec for '\(id.rawValue)'")
        }
        return spec
    }
}
