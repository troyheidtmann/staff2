import Foundation
import SwiftUI

// MARK: - Models

/// Represents a single note entry in the system
/// Contains content, metadata, and formatting utilities
struct Note: Identifiable, Codable {
    /// Unique identifier for the note
    let id: String
    
    /// Content of the note
    let text: String
    
    /// When the note was created
    let timestamp: Date
    
    /// Who created the note
    let author: String
    
    /// Formatted date string for UI display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

/// Collection of notes for a specific client
/// Groups notes by type (conversation and status)
struct ClientNotes: Codable {
    /// Associated client identifier
    let clientId: String
    
    /// Array of conversation notes
    var conversation: [Note]
    
    /// Array of status/creative notes
    var status: [Note]
}

/// Types of notes supported by the system
enum NoteType: String, Codable, CaseIterable {
    /// General conversation or interaction notes
    case conversation = "conversation"
    
    /// Status updates or creative content
    case status = "status"
    
    /// Display title for the note type
    var title: String {
        switch self {
        case .conversation: return "Conversation"
        case .status: return "Status"
        }
    }
}

/// AI-generated note recommendation
struct AIRecommendation: Identifiable, Codable {
    /// Unique identifier
    let id: String
    
    /// Recommended note content
    let text: String
    
    /// Type of note being recommended
    let type: NoteType
    
    /// Whether the recommendation has been accepted
    var isAccepted: Bool
    
    /// Maps Swift property names to JSON keys
    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case type
        case isAccepted = "is_accepted"
    }
}

// MARK: - ViewModel

/// View model managing quick notes functionality
/// Handles data fetching, state management, and business logic
class QuickNotesViewModel: ObservableObject {
    /// Available clients
    @Published var clients: [Client] = []
    
    /// Notes for the selected client
    @Published var clientNotes: ClientNotes?
    
    /// Current search query
    @Published var searchText = ""
    
    /// Current conversation note draft
    @Published var conversationNote = ""
    
    /// Current status note draft
    @Published var statusNote = ""
    
    /// Whether notes modal is showing
    @Published var showingNotes = false
    
    /// Loading state indicator
    @Published var isLoading = false
    
    /// Current error message
    @Published var error: String?
    
    /// Selected date for note filtering
    @Published var selectedDate: Date = Date()
    
    /// AI analysis notes
    @Published var aiAnalysisNotes: [AIAnalysisNote] = []
    
    /// Shared client manager instance
    private let clientManager: SharedClientManager
    
    /// Initializes the view model
    /// - Parameter clientManager: Optional client manager instance
    init(clientManager: SharedClientManager = .shared) {
        self.clientManager = clientManager
    }
    
    /// Filtered list of clients based on search text
    var filteredClients: [Client] {
        if searchText.count < 4 {
            return []
        }
        return clients.filter { client in
            client.fullName.lowercased().contains(searchText.lowercased())
        }
    }
    
    /// Fetches available clients from the API
    @MainActor
    func fetchClients() {
        isLoading = true
        error = nil
        
        _Concurrency.Task {
            do {
                clients = try await NotesAPIClient.shared.fetchClients()
                isLoading = false
            } catch {
                self.error = "Failed to load clients: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    /// Fetches notes for a specific client
    /// - Parameter clientId: Client identifier
    @MainActor
    func fetchNotes(for clientId: String) {
        print("fetchNotes: Starting fetch for client \(clientId)")
        isLoading = true
        error = nil
        
        _Concurrency.Task {
            do {
                print("fetchNotes: Attempting to fetch notes")
                let notes = try await NotesAPIClient.shared.fetchNotes(clientId: clientId, date: selectedDate)
                print("fetchNotes: Successfully fetched notes - Conversation: \(notes.conversation.count), Status: \(notes.status.count)")
                clientNotes = notes
                isLoading = false
            } catch {
                print("fetchNotes: Error fetching notes - \(error)")
                self.error = "Failed to load notes: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    /// Adds a new note for the selected client
    /// - Parameters:
    ///   - type: Type of note to add
    ///   - text: Content of the note
    @MainActor
    func addNote(type: NoteType, text: String) {
        guard let clientId = clientManager.selectedClient?.clientId, !text.isEmpty else { return }
        
        let note = Note(
            id: UUID().uuidString,
            text: text,
            timestamp: Date(),
            author: "Current User" // Replace with actual user info
        )
        
        _Concurrency.Task {
            do {
                try await NotesAPIClient.shared.addNote(clientId: clientId, type: type, note: note)
                // Refresh notes after adding
                await fetchNotes(for: clientId)
                
                // Clear the input field
                switch type {
                case .conversation:
                    conversationNote = ""
                case .status:
                    statusNote = ""
                }
            } catch {
                self.error = "Failed to add note: \(error.localizedDescription)"
            }
        }
    }
    
    /// Formats text with proper line breaks
    /// - Parameter text: Raw text to format
    /// - Returns: Formatted text with line breaks
    func formatWithLineBreaks(_ text: String) -> String {
        // First normalize all whitespace and remove any existing line breaks
        let normalizedText = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        // Split by sentence endings (., !, ?) but keep the punctuation
        var sentences: [String] = []
        var currentSentence = ""
        
        for char in normalizedText {
            currentSentence.append(char)
            if ".!?".contains(char) {
                // When we hit sentence-ending punctuation, trim and add to sentences
                sentences.append(currentSentence.trimmingCharacters(in: .whitespaces))
                currentSentence = ""
            }
        }
        
        // Add any remaining text as the last sentence
        if !currentSentence.isEmpty {
            sentences.append(currentSentence.trimmingCharacters(in: .whitespaces))
        }
        
        // Filter out empty sentences and join with double newlines
        return sentences
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
    
    /// Fetches AI recommendations for notes
    /// - Parameter type: Optional note type to filter recommendations
    @MainActor
    func fetchAIRecommendations(for type: NoteType? = nil) {
        guard let clientId = clientManager.selectedClient?.clientId else {
            print("fetchAIRecommendations: No client selected")
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: selectedDate)
        
        _Concurrency.Task {
            do {
                let notes = try await NotesAPIClient.shared.fetchAIAnalysis(clientId: clientId, date: dateString)
                if let note = notes.first {
                    let cleanedText = note.text.dropFirst(11)
                    switch type {
                    case .conversation:
                        self.conversationNote = formatWithLineBreaks(String(cleanedText))
                    case .status:
                        self.statusNote = formatWithLineBreaks(String(cleanedText))
                    case .none:
                        break
                    }
                }
            } catch {
                print("fetchAIRecommendations error: \(error)")
                self.error = "Failed to load AI suggestions: \(error.localizedDescription)"
            }
        }
    }
    
    /// Fetches AI analysis for the current client and date
    @MainActor
    func fetchAIAnalysis() async {
        guard let clientId = clientManager.selectedClient?.clientId else {
            print("fetchAIAnalysis: No client selected")
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: selectedDate)
        
        print("fetchAIAnalysis: Starting fetch for client \(clientId) on date \(dateString)")
        isLoading = true
        error = nil
        
        do {
            let notes = try await NotesAPIClient.shared.fetchAIAnalysis(clientId: clientId, date: dateString)
            await MainActor.run {
                self.aiAnalysisNotes = notes
                self.isLoading = false
            }
            print("fetchAIAnalysis: Received \(notes.count) notes")
        } catch APIError.invalidResponse {
            print("fetchAIAnalysis: Invalid date format or response")
            await MainActor.run {
                self.error = "Invalid date format or response"
                self.isLoading = false
            }
        } catch APIError.serverError(let code) {
            print("fetchAIAnalysis: Server error \(code)")
            await MainActor.run {
                self.error = "Server error occurred. Please try again later."
                self.isLoading = false
            }
        } catch {
            print("fetchAIAnalysis error: \(error)")
            await MainActor.run {
                self.error = "Failed to load AI analysis: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    /// Fetches all data for the selected date
    @MainActor
    func fetchAllForDate() {
        guard let clientId = clientManager.selectedClient?.clientId else {
            print("fetchAllForDate: No client selected")
            return
        }
        
        print("fetchAllForDate: Fetching for client \(clientId) on date \(selectedDate)")
        
        _Concurrency.Task {
            print("fetchAllForDate: Starting note fetch")
            await fetchNotes(for: clientId)
            print("fetchAllForDate: Starting AI analysis fetch")
            await fetchAIAnalysis()
            print("fetchAllForDate: Completed all fetches")
        }
    }
}

// MARK: - Views

/// Main view for quick notes functionality
/// Provides client selection and note input interface
struct QuickNotesView: View {
    /// View model managing notes state
    @StateObject private var viewModel = QuickNotesViewModel()
    
    /// Shared client manager
    @StateObject private var clientManager = SharedClientManager.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Client Search/Selection
                ClientSearchView(viewModel: viewModel, clientManager: clientManager)
                
                if let client = clientManager.selectedClient {
                    // Quick Note Input Section
                    QuickNoteInputSection(viewModel: viewModel)
                    
                    // View Notes Button
                    Button(action: {
                        viewModel.showingNotes = true
                    }) {
                        Text("View All Notes")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                } else {
                    Text("Select a client to add notes")
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            .navigationTitle("Quick Notes")
            .sheet(isPresented: $viewModel.showingNotes) {
                NotesModalView(viewModel: viewModel)
            }
            .onAppear {
                viewModel.fetchClients()
            }
        }
    }
}

/// Client search and selection interface
struct ClientSearchView: View {
    /// View model reference
    @ObservedObject var viewModel: QuickNotesViewModel
    
    /// Client manager reference
    @ObservedObject var clientManager: SharedClientManager
    
    /// Local search text state
    @State private var localSearchText: String = ""
    
    /// Search field focus state
    @FocusState private var isSearchFocused: Bool
    
    /// Whether search results are expanded
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack {
            HStack {
                if let selectedClient = clientManager.selectedClient {
                    HStack {
                        Text(selectedClient.fullName)
                        Spacer()
                        Button(action: {
                            clientManager.selectedClient = nil
                            isExpanded = true
                            isSearchFocused = true
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal)
                    .onTapGesture {
                        isExpanded = true
                        isSearchFocused = true
                    }
                } else {
                    TextField("Search clients...", text: $localSearchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($isSearchFocused)
                        .onChange(of: localSearchText) { newValue in
                            viewModel.searchText = newValue
                            isExpanded = true
                        }
                        .padding(.horizontal)
                }
            }
            
            if isExpanded {
                if localSearchText.count < 4 {
                    Text("Type at least 4 characters to search")
                        .foregroundColor(.gray)
                        .padding()
                } else if viewModel.filteredClients.isEmpty {
                    Text("No clients found")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack {
                            ForEach(viewModel.filteredClients) { client in
                                Button(action: {
                                    clientManager.selectedClient = client
                                    viewModel.fetchNotes(for: client.clientId)
                                    viewModel.fetchAIRecommendations()
                                    isSearchFocused = false
                                    localSearchText = ""
                                    viewModel.searchText = ""
                                    isExpanded = false
                                }) {
                                    HStack {
                                        Text(client.fullName)
                                        Spacer()
                                        if clientManager.selectedClient?.id == client.id {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
    }
}

/// Note input interface with AI suggestions
struct QuickNoteInputSection: View {
    /// View model reference
    @ObservedObject var viewModel: QuickNotesViewModel
    @State private var showingAIAnalysis = false
    @FocusState private var conversationNoteFocused: Bool
    @FocusState private var statusNoteFocused: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // Date Picker
            HStack {
                Text("Select Date")
                    .font(.headline)
                Spacer()
                DatePicker(
                    "",
                    selection: $viewModel.selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.compact)
                .labelsHidden()
            }
            .padding(.horizontal)
            .onChange(of: viewModel.selectedDate) { _ in
                viewModel.fetchAllForDate()
            }
            
            // AI Analysis Button
            Button(action: {
                showingAIAnalysis = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                    Text("View AI Analysis")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal)
            .sheet(isPresented: $showingAIAnalysis) {
                AIAnalysisView(viewModel: viewModel)
            }
            
            // Notes Section
            VStack(spacing: 16) {
                // Conversation Note
                VStack(alignment: .leading, spacing: 8) {
                    Text("Conversation Note")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    HStack(spacing: 8) {
                        TextEditor(text: $viewModel.conversationNote)
                            .frame(height: 100)
                            .padding(8)
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                            .focused($conversationNoteFocused)
                        
                        VStack(spacing: 8) {
                            Button(action: {
                                viewModel.fetchAIRecommendations(for: .conversation)
                            }) {
                                Circle()
                                    .fill(Color.purple)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "brain")
                                            .foregroundColor(.white)
                                            .font(.system(size: 20, weight: .semibold))
                                    )
                            }
                            
                            Button(action: {
                                viewModel.addNote(type: .conversation, text: viewModel.conversationNote)
                                conversationNoteFocused = false
                            }) {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .foregroundColor(.white)
                                            .font(.system(size: 20, weight: .semibold))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Status Note
                VStack(alignment: .leading, spacing: 8) {
                    Text("Creative Note")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    HStack(spacing: 8) {
                        TextEditor(text: $viewModel.statusNote)
                            .frame(height: 100)
                            .padding(8)
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                            .focused($statusNoteFocused)
                        
                        VStack(spacing: 8) {
                            Button(action: {
                                viewModel.addNote(type: .status, text: viewModel.statusNote)
                                statusNoteFocused = false
                            }) {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .foregroundColor(.white)
                                            .font(.system(size: 20, weight: .semibold))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

/// AI analysis display interface
struct AIAnalysisView: View {
    /// View model reference
    @ObservedObject var viewModel: QuickNotesViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.aiAnalysisNotes, id: \.timestamp) { note in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "brain")
                                            .foregroundColor(.purple)
                                        Text("AI Analysis")
                                            .font(.caption)
                                            .foregroundColor(.purple)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.purple.opacity(0.1))
                                            .cornerRadius(4)
                                        Spacer()
                                        Text(note.timestamp, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Text(note.text.dropFirst(11))
                                        .font(.body)
                                }
                                .padding()
                                .background(Color.purple.opacity(0.05))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("AI Analysis")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

/// Modal view for displaying all notes
struct NotesModalView: View {
    /// View model reference
    @ObservedObject var viewModel: QuickNotesViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack {
                if let notes = viewModel.clientNotes {
                    ScrollView {
                        VStack(spacing: 20) {
                            NotesSectionView(title: "Conversation Notes", notes: notes.conversation)
                            NotesSectionView(title: "Creative Notes", notes: notes.status)
                        }
                        .padding()
                    }
                } else {
                    Text("No notes available")
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Notes")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    if gesture.translation.height > 50 {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
        )
    }
}

/// Reusable section for displaying notes
struct NotesSectionView: View {
    /// Section title
    let title: String
    
    /// Notes to display
    let notes: [Note]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 5) {
                    if note.author == "AI" {
                        HStack {
                            Image(systemName: "brain")
                                .foregroundColor(.purple)
                            Text("AI Analysis")
                                .font(.caption)
                                .foregroundColor(.purple)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .padding(.bottom, 4)
                    }
                    
                    Text(note.text)
                        .font(.body)
                    
                    HStack {
                        Text(note.author)
                            .font(.caption)
                            .foregroundColor(note.author == "AI" ? .purple : .gray)
                        Spacer()
                        Text(note.formattedDate)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(note.author == "AI" ? Color.purple.opacity(0.05) : Color(.systemGray6))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(note.author == "AI" ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Preview
struct QuickNotesView_Previews: PreviewProvider {
    static var previews: some View {
        QuickNotesView()
    }
} 