import Foundation
import SwiftUI

/// Comprehensive error handling enumeration for all API operations
/// - invalidURL: The URL construction failed
/// - networkError: Underlying network layer error occurred
/// - invalidResponse: Server response was malformed or unexpected
/// - decodingError: JSON parsing/decoding failed
/// - noData: Server returned empty response
/// - serverError: Server returned error status code
/// - unauthorized: Authentication token invalid or expired
enum APIError: Error {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case noData
    case serverError(Int)
    case unauthorized
}

/// Custom coding key implementation for flexible JSON parsing
private struct CustomCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - AI Notes Models

/// Represents an AI-generated analysis note
/// - text: The content of the analysis
/// - timestamp: When the analysis was generated
/// - type: Classification of the analysis
public struct AIAnalysisNote: Codable {
    let text: String
    let timestamp: Date
    let type: String
    
    init(text: String, timestamp: Date = Date(), type: String = "analysis") {
        self.text = text
        self.timestamp = timestamp
        self.type = type
    }
}

/// Response structure for AI analysis endpoints
struct AIAnalysisResponse: Codable {
    let notes: [String]
}

/// Response structure for assignee search endpoints
struct AssigneesResponse: Codable {
    let assignees: [TaskAssignee]
}

/// Core API client responsible for all network operations
/// Thread-safe singleton implementation with centralized auth management
class NotesAPIClient {
    /// Shared singleton instance
    static let shared = NotesAPIClient()
    
    /// Base URL for all API endpoints
    let baseURL = "https://track.snapped.cc"
    
    /// JWT auth token for request authentication
    private var authToken: String?
    
    /// Private initializer enforcing singleton pattern
    private init() {}
    
    /// Sets the authentication token for subsequent requests
    /// - Parameter token: JWT token string
    func setAuthToken(_ token: String) {
        self.authToken = token
    }
    
    // MARK: - Private Helpers
    
    /// Constructs a standardized URLRequest with auth and content headers
    /// - Parameters:
    ///   - endpoint: API endpoint path
    ///   - method: HTTP method (default: GET)
    /// - Returns: Configured URLRequest
    private func makeRequest(endpoint: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)/\(endpoint)")!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
    
    /// Generic request handler with type-safe response parsing
    /// - Parameters:
    ///   - endpoint: API endpoint path
    ///   - method: HTTP method
    ///   - body: Optional request body
    /// - Returns: Decoded response of type T
    /// - Throws: APIError for network or parsing failures
    private func performRequest<T: Codable>(endpoint: String, method: String = "GET", body: Encodable? = nil) async throws -> T {
        var request = makeRequest(endpoint: endpoint, method: method)
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    // MARK: - Client APIs
    
    /// Fetches all available clients
    /// - Returns: Array of Client objects
    /// - Throws: APIError for network or parsing failures
    func fetchClients() async throws -> [Client] {
        guard let url = URL(string: "\(baseURL)/api/desktop-upload/users") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            print("Fetching clients from: \(url.absoluteString)")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response type")
                throw APIError.invalidResponse
            }
            
            print("Response status code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                if let errorData = String(data: data, encoding: .utf8) {
                    print("Error response: \(errorData)")
                }
                throw APIError.invalidResponse
            }
            
            guard !data.isEmpty else {
                print("Received empty data")
                throw APIError.noData
            }
            
            if let dataString = String(data: data, encoding: .utf8) {
                print("Raw response data: \(dataString)")
            }
            
            struct APIResponse: Codable {
                let status: String
                let users: [Client]
            }
            
            let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
            
            print("Successfully decoded \(apiResponse.users.count) clients")
            return apiResponse.users
            
        } catch let error as APIError {
            print("API Error: \(error.localizedDescription)")
            throw error
        } catch let error as DecodingError {
            print("Decoding Error: \(error)")
            throw APIError.decodingError(error)
        } catch {
            print("Network Error: \(error)")
            throw APIError.networkError(error)
        }
    }
    
    /// Fetches notes for a specific client and date
    /// - Parameters:
    ///   - clientId: Unique identifier for the client
    ///   - date: Date to fetch notes for
    /// - Returns: ClientNotes containing conversation and status notes
    /// - Throws: APIError for network or parsing failures
    func fetchNotes(clientId: String, date: Date) async throws -> ClientNotes {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
        // First fetch regular notes
        let url = URL(string: "\(baseURL)/api/lead/notes/\(clientId)/\(dateString)")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        // First try to decode as regular notes format
        struct RegularNote: Codable {
            let text: String
            let timestamp: String
            let author: String
        }
        
        struct RegularNotesData: Codable {
            let _id: String
            let client_id: String
            let conversation: [RegularNote]
            let status: [RegularNote]
        }
        
        struct RegularAPIResponse: Codable {
            let status: String
            let data: RegularNotesData
        }
        
        do {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Raw Notes API Response: \(jsonString)")
            }
            
            let decoder = JSONDecoder()
            
            // Try to decode as regular notes first
            let regularResponse = try decoder.decode(RegularAPIResponse.self, from: data)
            
            // Convert regular notes
            let conversationNotes = regularResponse.data.conversation.map { note -> Note in
                let timestamp = ISO8601DateFormatter().date(from: note.timestamp) ?? Date()
                return Note(
                    id: UUID().uuidString,
                    text: note.text,
                    timestamp: timestamp,
                    author: note.author
                )
            }
            
            let statusNotes = regularResponse.data.status.map { note -> Note in
                let timestamp = ISO8601DateFormatter().date(from: note.timestamp) ?? Date()
                return Note(
                    id: UUID().uuidString,
                    text: note.text,
                    timestamp: timestamp,
                    author: note.author
                )
            }
            
            // Now fetch AI analysis from message store
            let messageStoreUrl = URL(string: "\(baseURL)/api/message-store/\(clientId)/\(dateString)")!
            var messageStoreRequest = URLRequest(url: messageStoreUrl)
            messageStoreRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = authToken {
                messageStoreRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            print("Fetching message store from: \(messageStoreUrl.absoluteString)")
            let (messageData, messageResponse) = try await URLSession.shared.data(for: messageStoreRequest)
            
            if let messageString = String(data: messageData, encoding: .utf8) {
                print("Raw Message Store Response: \(messageString)")
            }
            
            guard let messageHttpResponse = messageResponse as? HTTPURLResponse,
                  messageHttpResponse.statusCode == 200 else {
                print("Message store request failed")
                return ClientNotes(
                    clientId: regularResponse.data.client_id,
                    conversation: conversationNotes,
                    status: statusNotes
                )
            }
            
            // Define structures for message store
            struct Session: Codable {
                let type: String
                let content: String?
                let timestamp: String?
            }
            
            struct MessageStoreResponse: Codable {
                let sessions: [String: [Session]]
            }
            
            let messageStoreResponse = try decoder.decode(MessageStoreResponse.self, from: messageData)
            var aiNotes: [Note] = []
            
            for (_, sessions) in messageStoreResponse.sessions {
                for session in sessions {
                    if session.type == "ai_analysis",
                       let content = session.content,
                       let timestamp = session.timestamp {
                        let sections = content.components(separatedBy: "NOTES:")
                        if sections.count > 1 {
                            let noteText = sections[1].trimmingCharacters(in: .whitespacesAndNewlines)
                            if !noteText.isEmpty && noteText.lowercased() != "none" {
                                let note = Note(
                                    id: UUID().uuidString,
                                    text: noteText,
                                    timestamp: ISO8601DateFormatter().date(from: timestamp) ?? Date(),
                                    author: "AI"
                                )
                                aiNotes.append(note)
                            }
                        }
                    }
                }
            }
            
            // Combine regular notes with AI notes
            let allConversationNotes = conversationNotes + aiNotes
            return ClientNotes(
                clientId: regularResponse.data.client_id,
                conversation: allConversationNotes.sorted { $0.timestamp > $1.timestamp },
                status: statusNotes
            )
            
        } catch {
            print("Decoding error: \(error)")
            throw APIError.decodingError(error)
        }
    }
    
    /// Adds a new note for a client
    /// - Parameters:
    ///   - clientId: Unique identifier for the client
    ///   - type: Type of note (conversation/status)
    ///   - note: Note content and metadata
    /// - Throws: APIError for network failures
    func addNote(clientId: String, type: NoteType, note: Note) async throws {
        let url = URL(string: "\(baseURL)/api/lead/notes/\(clientId)/\(type.rawValue)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let noteData = [
            "text": note.text,
            "author": note.author,
            "timestamp": ISO8601DateFormatter().string(from: note.timestamp)
        ]
        
        request.httpBody = try JSONEncoder().encode(noteData)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
    }
    
    /// Fetches AI-generated analysis for a client
    /// - Parameters:
    ///   - clientId: Unique identifier for the client
    ///   - date: Date string in yyyy-MM-dd format
    /// - Returns: Array of AIAnalysisNote objects
    /// - Throws: APIError for network or parsing failures
    func fetchAIAnalysis(clientId: String, date: String) async throws -> [AIAnalysisNote] {
        let endpoint = "api/messages/ai-notes/\(clientId)/\(date)"
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            print("Fetching AI analysis from: \(url.absoluteString)")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response type")
                throw APIError.invalidResponse
            }
            
            print("Response status code: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 400 {
                throw APIError.invalidResponse
            }
            
            if httpResponse.statusCode == 500 {
                if let errorData = String(data: data, encoding: .utf8) {
                    print("Server error: \(errorData)")
                }
                throw APIError.serverError(httpResponse.statusCode)
            }
            
            guard httpResponse.statusCode == 200 else {
                throw APIError.invalidResponse
            }
            
            if let dataString = String(data: data, encoding: .utf8) {
                print("Raw response data: \(dataString)")
            }
            
            let decoder = JSONDecoder()
            let apiResponse = try decoder.decode(AIAnalysisResponse.self, from: data)
            
            // Convert string notes to AIAnalysisNote objects
            let analysisNotes = apiResponse.notes.map { noteText in
                AIAnalysisNote(text: noteText)
            }
            
            print("Successfully decoded \(analysisNotes.count) AI notes")
            return analysisNotes
            
        } catch let error as APIError {
            print("API Error: \(error)")
            throw error
        } catch let error as DecodingError {
            print("Decoding Error: \(error)")
            throw APIError.decodingError(error)
        } catch {
            print("Network Error: \(error)")
            throw APIError.networkError(error)
        }
    }
    
    /// Fetches AI-generated recommendations
    /// - Parameters:
    ///   - clientId: Unique identifier for the client
    ///   - date: Date string in yyyy-MM-dd format
    /// - Returns: Array of AIRecommendation objects
    /// - Throws: APIError for network or parsing failures
    func fetchAIRecommendations(clientId: String, date: String) async throws -> [AIRecommendation] {
        let url = URL(string: "\(baseURL)/api/lead/notes/\(clientId)/ai-recommendations/\(date)")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        if let dataString = String(data: data, encoding: .utf8) {
            print("Raw AI recommendations response: \(dataString)")
        }
        
        struct SimpleResponse: Codable {
            let notes: [String]
        }
        
        let simpleResponse = try JSONDecoder().decode(SimpleResponse.self, from: data)
        
        // Convert string notes to AIRecommendation objects
        return simpleResponse.notes.map { noteText in
            AIRecommendation(
                id: UUID().uuidString,
                text: noteText,
                type: .conversation,
                isAccepted: false
            )
        }
    }
    
    // MARK: - Task APIs
    
    /// Creates a new task
    /// - Parameter task: Task object containing all task details
    /// - Throws: APIError for network failures
    func createTask(_ task: Task) async throws {
        let url = URL(string: "\(baseURL)/api/tasks")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(task)
        
        print("Creating task: \(task)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid response type")
            throw APIError.invalidResponse
        }
        
        print("Response status code: \(httpResponse.statusCode)")
        
        if let dataString = String(data: data, encoding: .utf8) {
            print("Raw create task response: \(dataString)")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
    
    /// Fetches tasks with optional filtering
    /// - Parameter filterType: Optional filter criteria
    /// - Returns: Array of Task objects
    /// - Throws: APIError for network or parsing failures
    func fetchTasks(filterType: String? = nil) async throws -> [Task] {
        var components = URLComponents(string: "\(baseURL)/api/tasks")!
        if let filterType = filterType {
            components.queryItems = [URLQueryItem(name: "filter_type", value: filterType)]
        }
        
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        print("Fetching tasks with filter: \(filterType ?? "none")")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid response type")
            throw APIError.invalidResponse
        }
        
        print("Response status code: \(httpResponse.statusCode)")
        
        if let dataString = String(data: data, encoding: .utf8) {
            print("Raw tasks response: \(dataString)")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode)
        }
        
        struct TasksResponse: Codable {
            let tasks: [Task]
        }
        
        let tasksResponse = try JSONDecoder().decode(TasksResponse.self, from: data)
        print("Fetched \(tasksResponse.tasks.count) tasks")
        return tasksResponse.tasks
    }
    
    /// Updates an existing task
    /// - Parameters:
    ///   - task: Updated task object
    ///   - taskId: Unique identifier for the task
    /// - Throws: APIError for network failures
    func updateTask(_ task: Task, taskId: String) async throws {
        let url = URL(string: "\(baseURL)/api/tasks/\(taskId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(task)
        
        print("Updating task \(taskId)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid response type")
            throw APIError.invalidResponse
        }
        
        print("Response status code: \(httpResponse.statusCode)")
        
        if let dataString = String(data: data, encoding: .utf8) {
            print("Raw update task response: \(dataString)")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
    
    /// Deletes a task
    /// - Parameter taskId: Unique identifier for the task
    /// - Throws: APIError for network failures
    func deleteTask(taskId: String) async throws {
        let url = URL(string: "\(baseURL)/api/tasks/\(taskId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        print("Deleting task \(taskId)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid response type")
            throw APIError.invalidResponse
        }
        
        print("Response status code: \(httpResponse.statusCode)")
        
        if let dataString = String(data: data, encoding: .utf8) {
            print("Raw delete task response: \(dataString)")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
    
    /// Fetches tasks for a specific client
    /// - Parameter clientId: Unique identifier for the client
    /// - Returns: Array of Task objects
    /// - Throws: APIError for network or parsing failures
    func fetchClientTasks(clientId: String) async throws -> [Task] {
        let url = URL(string: "\(baseURL)/api/tasks/client/\(clientId)")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        print("Fetching tasks for client: \(clientId)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid response type")
            throw APIError.invalidResponse
        }
        
        print("Response status code: \(httpResponse.statusCode)")
        
        if let dataString = String(data: data, encoding: .utf8) {
            print("Raw client tasks response: \(dataString)")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode)
        }
        
        struct TasksResponse: Codable {
            let tasks: [Task]
        }
        
        let tasksResponse = try JSONDecoder().decode(TasksResponse.self, from: data)
        print("Fetched \(tasksResponse.tasks.count) tasks for client")
        return tasksResponse.tasks
    }
    
    /// Fetches AI-generated task recommendations
    /// - Parameters:
    ///   - clientId: Unique identifier for the client
    ///   - date: Date string in yyyy-MM-dd format
    /// - Returns: Array of AITaskRecommendation objects
    /// - Throws: APIError for network or parsing failures
    func fetchAITaskRecommendations(clientId: String, date: String) async throws -> [AITaskRecommendation] {
        // Use the dedicated tasks endpoint instead of the notes endpoint
        let endpoint = "api/messages/tasks/\(clientId)/\(date)"
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        print("Fetching AI task recommendations from: \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid response type")
            throw APIError.invalidResponse
        }
        
        print("Response status code: \(httpResponse.statusCode)")
        
        if let dataString = String(data: data, encoding: .utf8) {
            print("Raw AI task recommendations response: \(dataString)")
        }
        
        // Handle 404 specifically to provide better error message
        if httpResponse.statusCode == 404 {
            print("Task recommendations endpoint not found - backend implementation required")
            return []
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        // Updated response structure - tasks are strings instead of objects
        struct TasksResponse: Codable {
            let tasks: [String]
        }
        
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(TasksResponse.self, from: data)
        
        return apiResponse.tasks.map { taskText in
            return AITaskRecommendation(
                id: UUID().uuidString,
                title: "AI Suggested Task",
                description: taskText,
                priority: .medium, // Default priority
                due_date: Date().addingTimeInterval(7 * 24 * 60 * 60), // Default to 1 week
                isAccepted: false
            )
        }
    }
    
    /// Searches for task assignees
    /// - Parameter query: Search query string
    /// - Returns: Array of matching TaskAssignee objects
    /// - Throws: APIError for network or parsing failures
    func searchAssignees(query: String) async throws -> [TaskAssignee] {
        let endpoint = "api/search_assignees"
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        print("Searching assignees with query: \(query)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid response type")
            throw APIError.invalidResponse
        }
        
        print("Response status code: \(httpResponse.statusCode)")
        
        if let dataString = String(data: data, encoding: .utf8) {
            print("Raw assignee search response: \(dataString)")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(AssigneesResponse.self, from: data)
        print("Found \(apiResponse.assignees.count) assignees")
        return apiResponse.assignees
    }
} 