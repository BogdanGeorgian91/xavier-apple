import Foundation
import NetworkExtension

final class FilterDataProvider: NEFilterDataProvider {
    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        let settings = NEFilterSettings(
            defaultAction: .allow,
            rules: []
        )
        apply(settings) { error in
            completionHandler(error)
        }
    }

    override func stopFilter(reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterAction {
        return .allow
    }
}