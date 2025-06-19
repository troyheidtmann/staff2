import Foundation
import SwiftUI

/// Manages the global state of client selection across the application
/// Thread-safe singleton implementation ensuring consistent client state
/// Uses SwiftUI's ObservableObject for reactive updates
class SharedClientManager: ObservableObject {
    /// Shared singleton instance
    /// Prevents multiple competing client managers and potential state inconsistencies
    static let shared = SharedClientManager()
    
    /// Currently selected client in the application
    /// Published property wrapper enables SwiftUI view updates on changes
    /// Nil when no client is selected
    @Published var selectedClient: Client?
    
    /// Private initializer enforcing singleton pattern
    /// Prevents external instantiation of the manager
    private init() {}
}

/// Represents a client entity in the system
/// Conforms to:
/// - Identifiable: Enables unique identification in SwiftUI lists
/// - Codable: Enables JSON serialization/deserialization
/// - Equatable: Enables value comparison
struct Client: Identifiable, Codable, Equatable {
    /// Unique identifier for the client
    /// Used for Identifiable conformance and database references
    let id: String
    
    /// Client's business identifier
    /// May be different from the internal id in some cases
    let clientId: String
    
    /// Client's display name
    /// Used in UI presentations and client-facing interfaces
    let name: String
    
    /// Computed property returning the full display name
    /// Currently returns the name directly, but can be extended for more complex naming logic
    var fullName: String { name }
    
    /// Defines the mapping between Swift property names and JSON keys
    /// Handles snake_case to camelCase conversion for API compatibility
    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case name
    }
    
    /// Custom decoder implementation
    /// Handles the mapping of API response to internal model
    /// - Parameter decoder: The decoder instance
    /// - Throws: DecodingError if required fields are missing or invalid
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let clientId = try container.decode(String.self, forKey: .clientId)
        self.id = clientId
        self.clientId = clientId
        self.name = try container.decode(String.self, forKey: .name)
    }
    
    /// Implements Equatable protocol
    /// Compares all properties to determine equality
    /// - Parameters:
    ///   - lhs: Left-hand side Client instance
    ///   - rhs: Right-hand side Client instance
    /// - Returns: Boolean indicating if clients are equal
    static func == (lhs: Client, rhs: Client) -> Bool {
        return lhs.id == rhs.id && lhs.clientId == rhs.clientId && lhs.name == rhs.name
    }
} 