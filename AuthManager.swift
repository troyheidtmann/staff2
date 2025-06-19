import Foundation
import SwiftUI

// AuthManager.swift
// Core authentication management singleton responsible for handling JWT token storage,
// validation, and synchronization with the Notes API client.

class AuthManager: ObservableObject {
    // MARK: - Singleton Instance
    /// Shared singleton instance ensuring consistent auth state across the application
    /// This prevents multiple competing auth managers and race conditions
    static let shared = AuthManager()
    
    // MARK: - Persistent Storage
    /// Persisted authentication token using SwiftUI's @AppStorage property wrapper
    /// Survives app restarts and provides immediate access to auth state
    /// Empty string indicates no valid authentication
    @AppStorage("authToken") private var storedToken: String = ""
    
    // MARK: - Initialization
    /**
     Private initializer enforcing singleton pattern
     Handles initial synchronization between persistent storage and API client
     
     Implementation details:
     - Checks if a token exists in persistent storage
     - If found, synchronizes it with the NotesAPIClient
     - Private access prevents external instantiation
     */
    private init() {
        if !storedToken.isEmpty {
            NotesAPIClient.shared.setAuthToken(storedToken)
        }
    }
    
    // MARK: - Public Interface
    
    /**
     Sets a new authentication token
     
     This method serves two critical purposes:
     1. Persists the token to device storage
     2. Synchronizes the token with the API client
     
     - Parameter token: JWT token string from authentication service
     
     Thread safety: This operation is atomic due to @AppStorage's thread-safe implementation
     */
    func setToken(_ token: String) {
        storedToken = token
        NotesAPIClient.shared.setAuthToken(token)
    }
    
    /**
     Retrieves the current authentication token
     
     - Returns: The current JWT token string, or empty string if not authenticated
     
     Security note: Consider evaluating token expiration before returning
     */
    func getToken() -> String {
        return storedToken
    }
    
    /**
     Checks if the user is currently authenticated
     
     Authentication is determined by the presence of a non-empty token
     
     - Returns: Boolean indicating authentication state
     
     Future improvements:
     - Add token expiration validation
     - Add token signature validation
     - Add token format validation
     */
    func isAuthenticated() -> Bool {
        return !storedToken.isEmpty
    }
    
    /**
     Clears the authentication state
     
     This method:
     1. Removes the token from persistent storage
     2. Invalidates the API client's authentication state
     
     Use cases:
     - User logout
     - Token invalidation
     - Security breach response
     */
    func clearToken() {
        storedToken = ""
        NotesAPIClient.shared.setAuthToken("")
    }
} 