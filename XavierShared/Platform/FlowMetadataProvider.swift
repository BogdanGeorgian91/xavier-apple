import Foundation

public protocol FlowMetadataProvider {
    var appIdentifier: String { get }
    var host: String? { get }
    var endpointIP: String? { get }
    var port: Int32? { get }
    var transportProtocol: String? { get }
    var direction: String? { get }
}