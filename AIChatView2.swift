//
//  AIChatView.swift
//  UploadApp
//
//  Created by Snapped on 2/27/25.
//

import SwiftUI
import Combine

// MARK: - Models

/// Represents a single message in the chat interface
/// Conforms to Identifiable for SwiftUI list rendering and Codable for API communication
struct Message: Identifiable, Codable {
    /// Unique identifier for the message
    let id: UUID
    
    /// Role of the message sender ("user" or "assistant")
    let role: String
    
    /// Content of the message
    let content: String
    
    /// Timestamp when the message was created
    let timestamp: Date
    
    /// Creates a new message with specified role, content, and timestamp
    /// - Parameters:
    ///   - role: The sender's role ("user" or "assistant")
    ///   - content: The message content
    ///   - timestamp: When the message was created
    init(role: String, content: String, timestamp: Date) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
    
    /// Defines the mapping between Swift property names and JSON keys
    /// Note: id is intentionally omitted as it's generated locally
    enum CodingKeys: String, CodingKey {
        case role, content, timestamp
    }
    
    /// Custom decoder implementation
    /// Generates new UUID when decoding from JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID() // Generate new UUID when decoding
        role = try container.decode(String.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }
    
    /// Custom encoder implementation
    /// Omits id from JSON encoding as it's not needed on the server
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

/// Request model for chat API endpoints
struct ChatRequest: Codable {
    /// Array of messages in the conversation
    let messages: [Message]
    
    /// Client identifier for the conversation
    let client_id: String
}

/// Response model from chat API endpoints
/// Handles multiple response formats for flexibility
struct ChatResponse: Codable {
    /// The message content from the assistant
    let message: String
    
    /// When the response was generated
    let timestamp: Date
    
    /// Defines the mapping between Swift property names and JSON keys
    /// Handles multiple possible field names for message content
    enum CodingKeys: String, CodingKey {
        case message, content, timestamp
    }
    
    /// Custom decoder implementation to handle multiple response formats
    /// Attempts to decode message from different field names
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode message directly first
        do {
            message = try container.decode(String.self, forKey: .message)
        } catch {
            // If that fails, try to decode content instead
            do {
                message = try container.decode(String.self, forKey: .content)
            } catch {
                // If both fail, try direct string response
                let singleContainer = try decoder.singleValueContainer()
                message = try singleContainer.decode(String.self)
            }
        }
        
        // Try to decode timestamp or use current date
        do {
            timestamp = try container.decode(Date.self, forKey: .timestamp)
        } catch {
            timestamp = Date()
        }
    }
    
    /// Standard encoder implementation
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encode(timestamp, forKey: .timestamp)
    }
    
    /// Creates a new response with specified message and timestamp
    init(message: String, timestamp: Date) {
        self.message = message
        self.timestamp = timestamp
    }
}

// MARK: - View Model

/// View model managing chat state and API communication
class AIChatViewModel: ObservableObject {
    /// Array of messages in the conversation
    @Published var messages: [Message] = []
    
    /// Current input message text
    @Published var inputMessage: String = ""
    
    /// Loading state for API requests
    @Published var isLoading = false
    
    /// Client identifier for the conversation
    private var clientId: String
    
    /// Shared API client instance
    private let apiClient = APIClient.shared
    
    /// Set of cancellables for managing async operations
    private var cancellables = Set<AnyCancellable>()
    
    /// Initializes view model with client ID
    init(clientId: String) {
        print("AIChatViewModel initialized with clientId: \(clientId)")
        self.clientId = clientId
    }
    
    /// Sends the current input message to the API
    /// Handles response processing and error handling
    func sendMessage() {
        guard !inputMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !clientId.isEmpty else {
            print("Error: Client ID is empty")
            messages.append(Message(
                role: "assistant",
                content: "Error: No client selected. Please select a client first.",
                timestamp: Date()
            ))
            return
        }
        
        print("Using client ID: \(clientId)")
        
        let userMessage = Message(
            role: "user",
            content: inputMessage,
            timestamp: Date()
        )
        
        messages.append(userMessage)
        inputMessage = ""
        isLoading = true
        
        // Prepare request
        let chatRequest = ChatRequest(
            messages: messages,
            client_id: clientId
        )
        
        // Debug print the request
        if let requestData = try? JSONEncoder().encode(chatRequest),
           let requestString = String(data: requestData, encoding: .utf8) {
            print("Sending request: \(requestString)")
        }
        
        // Convert to JSON data
        guard let jsonData = try? JSONEncoder().encode(chatRequest) else {
            print("Failed to encode chat request")
            isLoading = false
            return
        }
        
        // Create URL request
        guard let url = URL(string: "https://track.snapped.cc/api/chat") else {
            print("Invalid URL")
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AuthManager.shared.getToken())", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        
        // Debug print the full request
        print("Request URL: \(url)")
        print("Request Headers: \(request.allHTTPHeaderFields ?? [:])")
        if let bodyString = String(data: jsonData, encoding: .utf8) {
            print("Request Body: \(bodyString)")
        }
        
        // Make network request using Combine
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                switch completion {
                case .finished:
                    break
                case .failure(let error):
                    print("Network error: \(error)")
                    self?.isLoading = false
                    self?.messages.append(Message(
                        role: "assistant",
                        content: "Sorry, I encountered an error: \(error.localizedDescription)",
                        timestamp: Date()
                    ))
                }
            }, receiveValue: { [weak self] data in
                guard let self = self else { return }
                
                // For debugging - print the raw response
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Raw API response: \(responseString)")
                }
                
                // Try to decode using JSONDecoder
                do {
                    let decoder = JSONDecoder()
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                    decoder.dateDecodingStrategy = .formatted(dateFormatter)
                    
                    let response = try decoder.decode(ChatResponse.self, from: data)
                    
                    self.isLoading = false
                    self.messages.append(Message(
                        role: "assistant",
                        content: response.message,
                        timestamp: response.timestamp
                    ))
                } catch {
                    print("JSON decoding error: \(error)")
                    
                    // Fallback: try to interpret as plain string
                    if let responseString = String(data: data, encoding: .utf8) {
                        self.isLoading = false
                        self.messages.append(Message(
                            role: "assistant",
                            content: responseString,
                            timestamp: Date()
                        ))
                    }
                }
            })
            .store(in: &cancellables)
    }
    
    /// Updates the client ID for the conversation
    /// - Parameter newClientId: New client identifier
    func updateClientId(_ newClientId: String) {
        print("Updating clientId from \(clientId) to \(newClientId)")
        self.clientId = newClientId
    }
}

// MARK: - Main View

/// Main chat interface view
/// Displays messages and handles user input
struct AIChatView: View {
    /// View model managing chat state
    @StateObject private var viewModel: AIChatViewModel
    
    /// Shared client manager for user selection
    @StateObject private var clientManager = SharedClientManager.shared
    
    /// Focus state for input field
    @FocusState private var isInputFocused: Bool
    
    /// Environment dismiss action
    @Environment(\.dismiss) private var dismiss
    
    /// Current color scheme
    @Environment(\.colorScheme) private var colorScheme
    
    /// Primary blue color for the app
    private let appBlue = Color(red: 0.286, green: 0.384, blue: 0.749)
    
    /// Background color for the app
    private let appBackground = Color(red: 0.969, green: 0.969, blue: 0.969)
    
    /// Initializes the chat view
    init() {
        _viewModel = StateObject(wrappedValue: AIChatViewModel(clientId: ""))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let client = clientManager.selectedClient {
                    // Messages
                    GeometryReader { geometry in
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 16) {
                                    ForEach(viewModel.messages) { message in
                                        MessageBubble(message: message, appBlue: appBlue)
                                            .id(message.id)
                                            .frame(maxWidth: geometry.size.width)
                                    }
                                    
                                    if viewModel.isLoading {
                                        TypingIndicator(color: appBlue)
                                            .frame(maxWidth: geometry.size.width)
                                    }
                                }
                                .padding()
                            }
                            .onChange(of: viewModel.messages.count) { _ in
                                withAnimation(.easeOut(duration: 0.3)) {
                                    if let lastId = viewModel.messages.last?.id {
                                        proxy.scrollTo(lastId, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    .background(colorScheme == .dark ? Color.black : appBackground)
                    
                    // Input bar
                    InputBar(
                        text: $viewModel.inputMessage,
                        isFocused: _isInputFocused,
                        onSend: viewModel.sendMessage,
                        accentColor: appBlue
                    )
                    .background(colorScheme == .dark ? Color(white: 0.1) : .white)
                } else {
                    VStack(spacing: 20) {
              
                        
                        Text("Please select a client in the Notes tab to start chatting")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
            }
            .navigationTitle("AI Chat")
            .navigationBarTitleDisplayMode(.inline)
            .background(colorScheme == .dark ? Color.black : appBackground)
        }
        .onChange(of: clientManager.selectedClient) { newClient in
            if let clientId = newClient?.clientId {
                print("Selected client changed to: \(clientId)")
                viewModel.updateClientId(clientId)
            }
        }
    }
}

// MARK: - Supporting Views

/// Displays a single message bubble
/// Handles different styles for user and assistant messages
struct MessageBubble: View {
    /// Message to display
    let message: Message
    
    /// Primary accent color
    let appBlue: Color
    
    /// Current color scheme
    @Environment(\.colorScheme) private var colorScheme
    
    /// Background color for user messages
    private let userMessageColor = Color(red: 0.231, green: 0.231, blue: 0.239)
    
    /// Maximum width for message bubbles
    private let maxWidth: CGFloat = min(UIScreen.main.bounds.width * 0.75, 500)
    
    /// Cleans markdown formatting from text
    /// - Parameter text: Text to clean
    /// - Returns: Cleaned text without markdown syntax
    private func cleanMarkdownText(_ text: String) -> String {
        var cleanedText = text
        
        // Replace markdown headers
        cleanedText = cleanedText.replacingOccurrences(of: #"#{1,6}\s+"#, with: "", options: .regularExpression)
        
        // Replace bold/strong markers
        cleanedText = cleanedText.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
        
        // Replace italic/emphasis markers
        cleanedText = cleanedText.replacingOccurrences(of: #"\*(.+?)\*"#, with: "$1", options: .regularExpression)
        
        // Clean up list markers - use multiline option correctly
        let listOptions: NSRegularExpression.Options = [.anchorsMatchLines]
        if let regex = try? NSRegularExpression(pattern: #"^\s*[-*]\s+"#, options: listOptions) {
            cleanedText = regex.stringByReplacingMatches(in: cleanedText, 
                                                        options: [], 
                                                        range: NSRange(location: 0, length: cleanedText.utf16.count), 
                                                        withTemplate: "- ")
        }
        
        // Clean up numbered lists but keep the numbers - use multiline option correctly
        if let regex = try? NSRegularExpression(pattern: #"^\s*(\d+)\.\s+"#, options: listOptions) {
            cleanedText = regex.stringByReplacingMatches(in: cleanedText, 
                                                        options: [], 
                                                        range: NSRange(location: 0, length: cleanedText.utf16.count), 
                                                        withTemplate: "$1. ")
        }
        
        // Clean up backticks for code
        cleanedText = cleanedText.replacingOccurrences(of: "`", with: "")
        
        // Clean up triple backticks for code blocks
        cleanedText = cleanedText.replacingOccurrences(of: "```", with: "")
        
        return cleanedText
    }
    
    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer(minLength: 16)
            }
            
            VStack(alignment: message.role == "user" ? .trailing : .leading) {
                if message.role == "assistant" {
                    Text(cleanMarkdownText(message.content))
                        .foregroundColor(.white)
                        .padding()
                        .background(appBlue)
                        .cornerRadius(20)
                        .shadow(radius: colorScheme == .dark ? 1 : 3)
                        .textSelection(.enabled)
                } else {
                    Text(message.content)
                        .padding()
                        .foregroundColor(.white)
                        .background(userMessageColor)
                        .cornerRadius(20)
                        .shadow(radius: colorScheme == .dark ? 1 : 3)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: maxWidth, alignment: message.role == "user" ? .trailing : .leading)
            
            if message.role == "assistant" {
                Spacer(minLength: 16)
            }
        }
    }
}

/// Custom input bar for message composition
struct InputBar: View {
    /// Bound text input value
    @Binding var text: String
    
    /// Focus state for the input field
    @FocusState var isFocused: Bool
    
    /// Action to perform when sending message
    let onSend: () -> Void
    
    /// Accent color for UI elements
    let accentColor: Color
    
    /// Current color scheme
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Ask about your data, content, or if you need help with ideas", text: $text, axis: .vertical)
                .font(.system(size: 14))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(colorScheme == .dark ? Color(white: 0.2) : .white)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .focused($isFocused)
                .lineLimit(1...3)
                .padding(.vertical, 6)
                .accentColor(accentColor)
            
            Button(action: {
                onSend()
                isFocused = false
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 
                        (colorScheme == .dark ? Color(white: 0.3) : .gray.opacity(0.5)) : 
                        accentColor)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(colorScheme == .dark ? Color(white: 0.1) : .white)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.2)),
            alignment: .top
        )
    }
}

/// Animated typing indicator
struct TypingIndicator: View {
    /// Animation offset state
    @State private var animationOffset: CGFloat = 0
    
    /// Color for the indicator
    var color: Color
    
    /// Current color scheme
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(color.opacity(0.7))
                    .frame(width: 8, height: 8)
                    .offset(y: animationOffset)
                    .animation(
                        Animation.easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                        value: animationOffset
                    )
            }
        }
        .padding(12)
        .background(color.opacity(colorScheme == .dark ? 0.2 : 0.1))
        .cornerRadius(16)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                animationOffset = -5
            }
        }
    }
}

// MARK: - Preview
struct AIChatView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AIChatView()
        }
    }
}
