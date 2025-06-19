import SwiftUI
import Foundation

// MARK: - ViewModel

/// View model managing task creation and management functionality
/// Handles data fetching, state management, and task operations
@MainActor
class QuickTaskViewModel: ObservableObject {
    /// Current task title input
    @Published var taskTitle = ""
    
    /// Current task description input
    @Published var taskDescription = ""
    
    /// Selected priority level for the task
    @Published var selectedPriority: TaskPriority = .medium
    
    /// Due date for the task (defaults to 7 days from now)
    @Published var dueDate = Date().addingTimeInterval(7 * 24 * 60 * 60)
    
    /// Loading state indicator
    @Published var isLoading = false
    
    /// Current error message
    @Published var error: String?
    
    /// Whether to show success alert
    @Published var showSuccessAlert = false
    
    /// Selected date for filtering
    @Published var selectedDate = Date()
    
    /// AI-generated task recommendations
    @Published var aiRecommendations: [AITaskRecommendation] = []
    
    /// Whether to show recommendations sheet
    @Published var showingRecommendations = false
    
    /// Current assignee search query
    @Published var assigneeSearchText = ""
    
    /// Currently selected assignees
    @Published var assignees: [TaskAssignee] = []
    
    /// Search results for assignee lookup
    @Published var searchResults: [TaskAssignee] = []
    
    /// Whether assignee search is in progress
    @Published var isSearching = false
    
    /// Whether to show task list
    @Published var showingTaskList = false
    
    /// List of current tasks
    @Published var currentTasks: [Task] = []
    
    /// Whether tasks are being loaded
    @Published var isLoadingTasks = false
    
    /// Error message for task updates
    @Published var taskUpdateError: String?
    
    /// Shared client manager instance
    private let clientManager: SharedClientManager
    
    /// Initializes the view model
    /// - Parameter clientManager: Optional client manager instance
    init(clientManager: SharedClientManager = .shared) {
        self.clientManager = clientManager
    }
    
    /// Searches for assignees based on current search text
    @MainActor
    func searchAssignees() {
        guard assigneeSearchText.count >= 2 else {
            searchResults = []
            return
        }
        
        isSearching = true
        _Concurrency.Task {
            do {
                let results = try await NotesAPIClient.shared.searchAssignees(query: assigneeSearchText)
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                self.error = "Failed to search assignees: \(error.localizedDescription)"
                isSearching = false
            }
        }
    }
    
    /// Adds an assignee to the selected assignees list
    /// - Parameter assignee: Assignee to add
    func addAssignee(_ assignee: TaskAssignee) {
        if !assignees.contains(where: { $0.id == assignee.id }) {
            assignees.append(assignee)
        }
        assigneeSearchText = ""
        searchResults = []
    }
    
    /// Removes an assignee from the selected assignees list
    /// - Parameter assignee: Assignee to remove
    func removeAssignee(_ assignee: TaskAssignee) {
        assignees.removeAll(where: { $0.id == assignee.id })
    }
    
    /// Creates a new task with current input values
    @MainActor
    func createTask() async {
        guard let client = clientManager.selectedClient,
              !taskTitle.isEmpty else { return }
        
        isLoading = true
        error = nil
        
        // Always include the client as an assignee
        let clientAssignee = TaskAssignee(
            id: client.clientId,
            name: client.fullName,
            type: "client",
            clientId: client.clientId,
            employeeId: nil
        )
        
        // Combine client assignee with other assignees
        var allAssignees = [clientAssignee]
        allAssignees.append(contentsOf: assignees)
        
        let task = Task(
            id: UUID().uuidString,
            title: taskTitle,
            description: taskDescription,
            status: .pending,
            priority: selectedPriority,
            dueDate: dueDate,
            clientId: client.clientId,
            clientName: client.fullName,
            createdBy: "Current User",
            assignees: allAssignees
        )
        
        do {
            try await NotesAPIClient.shared.createTask(task)
            taskTitle = ""
            taskDescription = ""
            selectedPriority = .medium
            dueDate = Date().addingTimeInterval(7 * 24 * 60 * 60)
            assignees = []
            showSuccessAlert = true
            isLoading = false
        } catch {
            self.error = "Failed to create task: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    /// Fetches AI-generated task recommendations
    @MainActor
    func fetchAIRecommendations() {
        guard let clientId = clientManager.selectedClient?.clientId else { return }
        isLoading = true
        error = nil
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: selectedDate)
        
        _Concurrency.Task {
            do {
                aiRecommendations = try await NotesAPIClient.shared.fetchAITaskRecommendations(
                    clientId: clientId,
                    date: dateString
                )
                isLoading = false
                showingRecommendations = !aiRecommendations.isEmpty
            } catch {
                self.error = "Failed to load AI recommendations: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    /// Accepts an AI recommendation and populates form fields
    /// - Parameter recommendation: Recommendation to accept
    func acceptRecommendation(_ recommendation: AITaskRecommendation) {
        taskTitle = recommendation.title
        taskDescription = recommendation.description
        selectedPriority = recommendation.priority
        dueDate = recommendation.due_date
        
        if let index = aiRecommendations.firstIndex(where: { $0.id == recommendation.id }) {
            aiRecommendations[index].isAccepted = true
        }
    }
    
    /// Clears all form inputs
    func clearForm() {
        taskTitle = ""
        taskDescription = ""
        selectedPriority = .medium
        dueDate = Date().addingTimeInterval(7 * 24 * 60 * 60)
        selectedDate = Date()
        aiRecommendations = []
        showingRecommendations = false
    }
    
    /// Loads all tasks for the current client
    @MainActor
    func loadAllTasks() async {
        guard let clientId = clientManager.selectedClient?.clientId else { return }
        isLoadingTasks = true
        error = nil
        do {
            let tasks = try await NotesAPIClient.shared.fetchClientTasks(clientId: clientId)
            if let taskArray = tasks as? [Task] {
                currentTasks = taskArray
                print("Loaded \(currentTasks.count) tasks")
            }
            isLoadingTasks = false
        } catch {
            self.error = "Failed to load tasks: \(error.localizedDescription)"
            isLoadingTasks = false
            print("Error loading tasks: \(error)")
        }
    }
    
    /// Updates the status of a task
    /// - Parameters:
    ///   - task: Task to update
    ///   - newStatus: New status to set
    @MainActor
    func updateTaskStatus(_ task: Task, newStatus: TaskStatus) async {
        isLoading = true
        error = nil
        
        let updatedTask = Task(
            id: task.id,
            title: task.title,
            description: task.description,
            status: newStatus,
            priority: task.priority,
            dueDate: task.dueDate,
            clientId: task.clientId,
            clientName: task.clientName,
            createdBy: task.createdBy,
            assignees: task.assignees,
            createdAt: task.createdAt,
            updatedAt: Date(),
            visibleTo: task.visibleTo
        )
        
        do {
            try await NotesAPIClient.shared.updateTask(updatedTask, taskId: task.id)
            await loadAllTasks()
            isLoading = false
        } catch {
            self.error = "Failed to update task: \(error.localizedDescription)"
            isLoading = false
            print("Error updating task: \(error)")
        }
    }
    
    /// Updates task status to pending
    /// - Parameter task: Task to update
    @MainActor
    func updateToPending(_ task: Task) {
        _Concurrency.Task {
            await updateTaskStatus(task, newStatus: .pending)
        }
    }
    
    /// Updates task status to in progress
    /// - Parameter task: Task to update
    @MainActor
    func updateToInProgress(_ task: Task) {
        _Concurrency.Task {
            await updateTaskStatus(task, newStatus: .inProgress)
        }
    }
    
    /// Updates task status to completed
    /// - Parameter task: Task to update
    @MainActor
    func updateToCompleted(_ task: Task) {
        _Concurrency.Task {
            await updateTaskStatus(task, newStatus: .completed)
        }
    }
}

// MARK: - Views

/// Main view for task creation and management
struct QuickTaskView: View {
    /// View model managing task state
    @StateObject private var viewModel = QuickTaskViewModel()
    
    /// Shared client manager
    @StateObject private var clientManager = SharedClientManager.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if let client = clientManager.selectedClient {
                        // Task Input Form
                        TaskInputForm(viewModel: viewModel, clientManager: clientManager)
                    } else {
                        Text("Select a client in the Notes tab to create a task")
                            .foregroundColor(.gray)
                            .padding()
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Quick Task")
            .navigationBarItems(trailing:
                Button(action: {
                    viewModel.showingTaskList = true
                }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 20))
                }
            )
            .sheet(isPresented: $viewModel.showingTaskList) {
                TaskListView(viewModel: viewModel)
            }
            // Consolidated alerts into a single alert with different cases
            .alert(isPresented: Binding(
                get: { viewModel.showSuccessAlert || viewModel.error != nil },
                set: { newValue in
                    if !newValue {
                        viewModel.showSuccessAlert = false
                        viewModel.error = nil
                    }
                }
            )) {
                if viewModel.showSuccessAlert {
                    Alert(
                        title: Text("Success"),
                        message: Text("Task created successfully"),
                        dismissButton: .default(Text("OK"))
                    )
                } else if let error = viewModel.error {
                    Alert(
                        title: Text("Error"),
                        message: Text(error),
                        dismissButton: .default(Text("OK"))
                    )
                } else {
                    Alert(title: Text(""))  // Fallback case that should never happen
                }
            }
            .onAppear {
                if clientManager.selectedClient != nil {
                    viewModel.fetchAIRecommendations()
                }
            }
        }
    }
}

/// Form for task input and creation
struct TaskInputForm: View {
    /// View model reference
    @ObservedObject var viewModel: QuickTaskViewModel
    
    /// Client manager reference
    @ObservedObject var clientManager: SharedClientManager
    
    /// Focus state for title field
    @FocusState private var titleFocused: Bool
    
    /// Focus state for description field
    @FocusState private var descriptionFocused: Bool
    
    /// Current alert item
    @State private var alertItem: AlertItem?
    
    /// Alert item structure for error handling
    private struct AlertItem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }
    
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
                viewModel.fetchAIRecommendations()
            }
            
            // Task Input Section
            VStack(spacing: 16) {
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    TextField("Task title...", text: $viewModel.taskTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($titleFocused)
                        .padding(.horizontal)
                }
                
                // Description with AI Button
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Description")
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            _Concurrency.Task {
                                let dateFormatter = DateFormatter()
                                dateFormatter.dateFormat = "yyyy-MM-dd"
                                let dateString = dateFormatter.string(from: viewModel.selectedDate)
                                
                                if let recommendations = try? await NotesAPIClient.shared.fetchAITaskRecommendations(
                                    clientId: clientManager.selectedClient?.clientId ?? "",
                                    date: dateString
                                ), let firstTask = recommendations.first {
                                    viewModel.taskDescription = firstTask.description
                                    if viewModel.taskTitle.isEmpty {
                                        viewModel.taskTitle = firstTask.title
                                    }
                                } else {
                                    alertItem = AlertItem(
                                        title: "No AI Tasks Available",
                                        message: "No AI task recommendations are available for this client and date."
                                    )
                                }
                            }
                        }) {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Image(systemName: "brain")
                                        .foregroundColor(.white)
                                        .font(.system(size: 15, weight: .semibold))
                                )
                        }
                        .disabled(clientManager.selectedClient == nil)
                    }
                    .padding(.horizontal)
                    
                    TextEditor(text: $viewModel.taskDescription)
                        .frame(height: 100)
                        .focused($descriptionFocused)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
                
                // Priority
                VStack(alignment: .leading, spacing: 8) {
                    Text("Priority")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    Picker("Priority", selection: $viewModel.selectedPriority) {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            Text(priority.displayName)
                                .tag(priority)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                }
                
                // Add Assignee Search
                AssigneeSearchView(viewModel: viewModel)
                
                // Due Date
                VStack(alignment: .leading, spacing: 8) {
                    Text("Due Date")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    DatePicker(
                        "",
                        selection: $viewModel.dueDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .padding(.horizontal)
                }
            }
            
            // Create Button
            Button(action: {
                titleFocused = false
                descriptionFocused = false
                _Concurrency.Task {
                    await viewModel.createTask()
                }
            }) {
                Text("Create Task")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .disabled(clientManager.selectedClient == nil || viewModel.taskTitle.isEmpty)
        }
        .alert(item: $alertItem) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: viewModel.assigneeSearchText) { _ in
            viewModel.searchAssignees()
        }
        // Handle AI task button action
        .onChange(of: viewModel.selectedDate) { _ in
            viewModel.fetchAIRecommendations()
        }
    }
}

/// Search interface for task assignees
struct AssigneeSearchView: View {
    /// View model reference
    @ObservedObject var viewModel: QuickTaskViewModel
    
    /// Focus state for search field
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assignees")
                .font(.headline)
                .padding(.horizontal)
            
            // Selected Assignees
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.assignees) { assignee in
                        HStack {
                            Text(assignee.name)
                            Button(action: {
                                viewModel.removeAssignee(assignee)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal)
            }
            
            // Search Field
            TextField("Search people...", text: $viewModel.assigneeSearchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isSearchFocused)
                .onChange(of: viewModel.assigneeSearchText) { _ in
                    viewModel.searchAssignees()
                }
                .padding(.horizontal)
            
            // Search Results
            if !viewModel.searchResults.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.searchResults) { result in
                            Button(action: {
                                viewModel.addAssignee(result)
                                isSearchFocused = false
                            }) {
                                HStack {
                                    Text(result.name)
                                    Spacer()
                                    Text(result.type.capitalized)
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .shadow(radius: 2)
                .padding(.horizontal)
            }
        }
    }
}

/// View for displaying AI task recommendations
struct AITaskRecommendationsView: View {
    /// View model reference
    @ObservedObject var viewModel: QuickTaskViewModel
    
    /// Presentation mode for sheet dismissal
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
                            ForEach(viewModel.aiRecommendations) { recommendation in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "brain")
                                            .foregroundColor(.purple)
                                        Text("AI Recommendation")
                                            .font(.caption)
                                            .foregroundColor(.purple)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.purple.opacity(0.1))
                                            .cornerRadius(4)
                                        Spacer()
                                        Button(action: {
                                            viewModel.acceptRecommendation(recommendation)
                                            presentationMode.wrappedValue.dismiss()
                                        }) {
                                            Text("Use")
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.blue)
                                                .cornerRadius(8)
                                        }
                                    }
                                    
                                    Text(recommendation.title)
                                        .font(.headline)
                                    Text(recommendation.description)
                                        .font(.body)
                                        .foregroundColor(.gray)
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
            .navigationTitle("AI Recommendations")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

/// View for displaying list of tasks
struct TaskListView: View {
    /// View model reference
    @ObservedObject var viewModel: QuickTaskViewModel
    
    /// Environment dismiss action
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isLoadingTasks {
                    ProgressView()
                } else {
                    if let error = viewModel.error {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                            .multilineTextAlignment(.center)
                    }
                    List {
                        ForEach(viewModel.currentTasks) { task in
                            TaskRow(task: task, viewModel: viewModel)
                        }
                    }
                }
            }
            .navigationTitle("Tasks")
            .navigationBarItems(trailing: Button("Done", action: { dismiss() }))
            .task { await viewModel.loadAllTasks() }
        }
    }
}

/// Row view for individual task display
struct TaskRow: View {
    /// Task to display
    let task: Task
    
    /// View model reference
    @ObservedObject var viewModel: QuickTaskViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.headline)
            
            if !task.description.isEmpty {
                Text(task.description)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            HStack {
                Image(systemName: "person.circle")
                Text(task.clientName)
                    .font(.caption)
                
                Spacer()
                
                Menu {
                    Button("Pending") {
                        viewModel.updateToPending(task)
                    }
                    Button("In Progress") {
                        viewModel.updateToInProgress(task)
                    }
                    Button("Completed") {
                        viewModel.updateToCompleted(task)
                    }
                } label: {
                    Text(task.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
    }
}

// MARK: - Preview
struct QuickTaskView_Previews: PreviewProvider {
    static var previews: some View {
        QuickTaskView()
    }
} 
