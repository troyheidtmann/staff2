//
//  APIClient.swift
//  UploadApp
//
//  Created by Snapped on 12/23/24.
//

import Foundation
import UIKit

/// Response model for last file number endpoint
/// Contains the status of the request and the last file number used
struct LastFileResponse: Codable {
    /// Status message from the server
    let status: String
    
    /// The last file number used in the sequence
    let lastNumber: Int
}

/// Core API client for handling network requests
/// Thread-safe singleton implementation with comprehensive error handling and logging
class APIClient: ObservableObject {
    /// Shared singleton instance
    /// Prevents multiple competing API clients and ensures consistent state
    static let shared = APIClient()
    
    /// Private initializer enforcing singleton pattern
    private init() {}
    
    /// Base URL for all API endpoints
    private let baseURL = "https://track.snapped.cc"
    
    /// Custom error types for API operations
    /// Provides detailed error cases for network operations
    enum APIError: Error {
        /// URL construction failed
        case invalidURL
        
        /// Server response was malformed or unexpected
        case invalidResponse
        
        /// Server returned an error with message
        case serverError(String)
    }
    
    /// Performs a POST request to the specified endpoint
    /// - Parameters:
    ///   - endpoint: API endpoint path
    ///   - data: Request body that conforms to Encodable
    /// - Returns: Raw response data
    /// - Throws: APIError for network or encoding failures
    func post<T: Encodable>(_ endpoint: String, data: T) async throws -> Data {
        guard let url = URL(string: baseURL + endpoint) else {
            print("❌ Invalid URL: \(baseURL + endpoint)")
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONEncoder().encode(data)
            request.httpBody = jsonData
            
            // Pretty print the JSON for debugging
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("📤 Request data for \(endpoint):")
                print(jsonString)
            }
        } catch {
            print("❌ JSON encoding failed: \(error)")
            throw error
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                throw APIError.invalidResponse
            }
            
            print("📥 Response status: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 Response data: \(responseString)")
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ Server error: \(errorMessage)")
                throw APIError.serverError(errorMessage)
            }
            
            return data
        } catch {
            print("❌ Network request failed: \(error)")
            throw error
        }
    }
    
    /// Retrieves the last file number used for a specific client and folder
    /// - Parameters:
    ///   - clientId: Unique identifier for the client
    ///   - folder: Target folder name
    ///   - date: Optional date for filtering (format: "MMM dd, yyyy")
    /// - Returns: The last file number used
    /// - Throws: APIError for network or decoding failures
    func getLastFileNumber(clientId: String, folder: String, date: Date?) async throws -> Int {
        let baseURL = "https://track.snapped.cc"
        var endpoint = "/upload/last-file-number"
        
        // Add query parameters
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "clientId", value: clientId),
            URLQueryItem(name: "folder", value: folder)
        ]
        
        if let date = date {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM dd, yyyy"
            let dateString = dateFormatter.string(from: date)
            queryItems.append(URLQueryItem(name: "date", value: dateString))
        }
        
        var urlComponents = URLComponents(string: baseURL + endpoint)!
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }
        
        print("📊 Requesting last file number from: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Server error (\(httpResponse.statusCode)): \(errorMessage)")
            throw APIError.serverError(errorMessage)
        }
        
        do {
            let result = try JSONDecoder().decode(LastFileResponse.self, from: data)
            print("✅ Last file number response decoded: \(result.lastNumber)")
            return result.lastNumber
        } catch {
            print("❌ JSON Decoding error: \(error)")
            print("❌ Received data: \(String(data: data, encoding: .utf8) ?? "none")")
            throw APIError.serverError("JSON Decoding error")
        }
    }
    
    /// Resets the API client state by canceling all pending tasks
    /// Used for cleanup and state management
    /// Cancels only completed or canceling tasks to prevent data loss
    func resetState() {
        URLSession.shared.getAllTasks { tasks in
            tasks.forEach { task in
                if task.state == .completed || task.state == .canceling {
                    task.cancel()
                }
            }
        }
        print("🔄 API Client state cleaned up")
    }
    
    /// Performs a GET request to the specified endpoint
    /// - Parameters:
    ///   - endpoint: API endpoint path
    ///   - clientId: Client identifier for request header
    /// - Returns: Raw response data
    /// - Throws: APIError for network failures
    func get(_ endpoint: String, clientId: String) async throws -> Data {
        guard let url = URL(string: baseURL + endpoint) else {
            print("❌ Invalid URL: \(baseURL + endpoint)")
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientId, forHTTPHeaderField: "X-Client-ID")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                throw APIError.invalidResponse
            }
            
            print("📥 Response status: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 Response data: \(responseString)")
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ Server error: \(errorMessage)")
                throw APIError.serverError(errorMessage)
            }
            
            return data
        } catch {
            print("❌ Network request failed: \(error)")
            throw error
        }
    }
}  
