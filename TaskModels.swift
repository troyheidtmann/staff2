import Foundation
import SwiftUI

/// Represents a task entity in the system
/// Core model for task management functionality
/// Conforms to Identifiable for SwiftUI list rendering and Codable for JSON serialization
struct Task: Identifiable, Codable {
    /// MongoDB unique identifier
    let id: String
    
    /// Task title displayed in UI
    let title: String
    
    /// Detailed task description
    let description: String
    
    /// Current status of the task (pending, in_progress, completed)
    let status: TaskStatus
    
    /// Task priority level affecting UI presentation and sorting
    let priority: TaskPriority
    
    /// Due date for task completion
    let dueDate: Date
    
    /// Associated client's unique identifier
    let clientId: String
    
    /// User ID of task creator
    let createdBy: String
    
    /// List of users assigned to this task
    let assignees: [TaskAssignee]
    
    /// Timestamp of task creation (optional)
    let createdAt: Date?
    
    /// Timestamp of last task update (optional)
    let updatedAt: Date?
    
    /// List of user IDs with visibility permissions
    let visibleTo: [String]
    
    /// Computed property to get client name from assignees
    /// Returns "Unknown Client" if no client assignee is found
    var clientName: String {
        // Get client name from assignees
        assignees.first(where: { $0.type == "client" })?.name ?? "Unknown Client"
    }
    
    /// Maps Swift property names to JSON keys
    /// Handles MongoDB and API naming conventions
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title
        case description
        case status
        case priority
        case dueDate = "due_date"
        case clientId = "client_id"
        case createdBy = "created_by"
        case assignees
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case visibleTo = "visible_to"
    }
    
    /// Creates a new task with all required properties
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - title: Task title
    ///   - description: Task description
    ///   - status: Current task status
    ///   - priority: Task priority level
    ///   - dueDate: Task due date
    ///   - clientId: Associated client ID
    ///   - clientName: Client's display name
    ///   - createdBy: Creator's user ID
    ///   - assignees: List of task assignees
    ///   - createdAt: Creation timestamp (optional)
    ///   - updatedAt: Last update timestamp (optional)
    ///   - visibleTo: List of users with visibility permissions
    init(id: String, title: String, description: String, status: TaskStatus, priority: TaskPriority, dueDate: Date, clientId: String, clientName: String, createdBy: String, assignees: [TaskAssignee], createdAt: Date? = nil, updatedAt: Date? = nil, visibleTo: [String] = []) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.clientId = clientId
        self.createdBy = createdBy
        self.assignees = assignees
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.visibleTo = visibleTo
    }
    
    /// Decodes a task from JSON data
    /// Handles complex date parsing and client ID extraction
    /// - Parameter decoder: The decoder instance
    /// - Throws: DecodingError for invalid data or missing required fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle _id from MongoDB
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        status = try container.decode(TaskStatus.self, forKey: .status)
        priority = try container.decode(TaskPriority.self, forKey: .priority)
        
        // Handle date decoding
        let dateString = try container.decode(String.self, forKey: .dueDate)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateFormatter.date(from: dateString) {
            dueDate = date
        } else {
            throw DecodingError.dataCorruptedError(forKey: .dueDate, in: container, debugDescription: "Date string does not match format")
        }
        
        // Get assignees first since we need them for clientId
        assignees = try container.decode([TaskAssignee].self, forKey: .assignees)
        
        // Get clientId from first client assignee
        if let clientAssignee = assignees.first(where: { $0.type == "client" }) {
            clientId = clientAssignee.clientId ?? clientAssignee.id
        } else {
            throw DecodingError.keyNotFound(CodingKeys.clientId, .init(codingPath: container.codingPath, debugDescription: "No client ID found in assignees"))
        }
        
        createdBy = try container.decode(String.self, forKey: .createdBy)
        
        // Handle optional dates
        if let createdAtString = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = ISO8601DateFormatter().date(from: createdAtString)
        } else {
            createdAt = nil
        }
        
        if let updatedAtString = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = ISO8601DateFormatter().date(from: updatedAtString)
        } else {
            updatedAt = nil
        }
        
        visibleTo = try container.decodeIfPresent([String].self, forKey: .visibleTo) ?? []
    }
    
    /// Encodes the task to JSON format
    /// Handles date formatting and optional fields
    /// - Parameter encoder: The encoder instance
    /// - Throws: EncodingError for invalid data
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        
        // Handle date encoding
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: dueDate)
        try container.encode(dateString, forKey: .dueDate)
        
        try container.encode(clientId, forKey: .clientId)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encode(assignees, forKey: .assignees)
        
        // Handle optional dates
        if let createdAt = createdAt {
            try container.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
        }
        if let updatedAt = updatedAt {
            try container.encode(ISO8601DateFormatter().string(from: updatedAt), forKey: .updatedAt)
        }
        
        try container.encode(visibleTo, forKey: .visibleTo)
    }
}

/// Represents a user or client assigned to a task
/// Used for both employee and client assignments
struct TaskAssignee: Identifiable, Codable {
    /// Unique identifier for the assignee
    let id: String
    
    /// Display name of the assignee
    let name: String
    
    /// Type of assignee ("employee" or "client")
    let type: String
    
    /// Associated client ID (if type is "client")
    let clientId: String?
    
    /// Associated employee ID (if type is "employee")
    let employeeId: String?
    
    /// Maps Swift property names to JSON keys
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case clientId = "client_id"
        case employeeId = "employee_id"
    }
}

/// Represents the current status of a task
/// Used for task filtering and UI presentation
enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    /// Task has not been started
    case pending
    
    /// Task is currently being worked on
    case inProgress = "in_progress"
    
    /// Task has been finished
    case completed
    
    /// Unique identifier for SwiftUI
    var id: String { rawValue }
}

/// Represents the priority level of a task
/// Affects UI presentation and task sorting
enum TaskPriority: String, Codable, CaseIterable {
    /// Urgent tasks requiring immediate attention
    case high
    
    /// Standard priority tasks
    case medium
    
    /// Low urgency tasks
    case low
    
    /// User-friendly display name for the priority level
    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
    
    /// Associated color for UI presentation
    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }
}

/// Represents an AI-generated task recommendation
/// Used for suggesting new tasks based on AI analysis
struct AITaskRecommendation: Identifiable, Codable {
    /// Unique identifier for the recommendation
    let id: String
    
    /// Suggested task title
    let title: String
    
    /// Detailed task description from AI
    let description: String
    
    /// Suggested priority level
    let priority: TaskPriority
    
    /// Suggested due date
    let due_date: Date
    
    /// Whether the recommendation has been accepted
    var isAccepted: Bool
    
    /// Formatted due date string for UI display
    var formattedDueDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: due_date)
    }
} 