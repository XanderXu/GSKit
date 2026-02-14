import RealityKit

@available(macOS 26.0, *)
public enum GSKitRuntime {
    @MainActor
    public static func registerSystems() {
        GSSortComponent.registerComponent()
        GSModelDataComponent.registerComponent()
        GSSortingSystem.registerSystem()
    }
}
