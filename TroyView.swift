import SwiftUI

/// Main container view for the application
/// Manages tab-based navigation between major features and handles authentication setup
struct TroyView: View {
    /// Shared authentication manager for handling user sessions
    @StateObject private var authManager = AuthManager.shared
    
    /// Shared client manager for maintaining selected client state across views
    @StateObject private var clientManager = SharedClientManager.shared
    
    var body: some View {
        TabView {
            // Quick Notes Tab - For managing client notes and conversations
            QuickNotesView()
                .tabItem {
                    Label("Notes", systemImage: "note.text")
                }
            
            // Quick Tasks Tab - For managing client tasks and assignments
            QuickTaskView()
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }
            
            // AI Chat Tab - For AI-assisted conversations and analysis
            AIChatView()
                .tabItem {
                    Label("AI Chat", systemImage: "bubble.left.and.bubble.right")
                }
        }
        .onAppear {
            // Initialize authentication on app launch
            // Sets the JWT token for API authentication
            authManager.setToken("eyJraWQiOiIycjRDaE54TUZ3cEdjODU1bHJtZm5XSmpRcmN3NG1OUUpSQ09SbFdLdmNVPSIsImFsZyI6IlJTMjU2In0.eyJzdWIiOiI1MTViNjU3MC1hMDMxLTcwZDctY2QyZS04MzU4ZTRlODgwZDIiLCJjb2duaXRvOmdyb3VwcyI6WyJBRE1JTiIsIkRSRUFNIl0sImVtYWlsX3ZlcmlmaWVkIjp0cnVlLCJpc3MiOiJodHRwczpcL1wvY29nbml0by1pZHAudXMtZWFzdC0yLmFtYXpvbmF3cy5jb21cL3VzLWVhc3QtMl9pSWZ3U3NkQ1UiLCJwaG9uZV9udW1iZXJfdmVyaWZpZWQiOmZhbHNlLCJjdXN0b206VXNlcklEIjoidGgxMDAyMTk5NCIsImNvZ25pdG86dXNlcm5hbWUiOiI1MTViNjU3MC1hMDMxLTcwZDctY2QyZS04MzU4ZTRlODgwZDIiLCJnaXZlbl9uYW1lIjoiVHJveSIsIm9yaWdpbl9qdGkiOiJkYmNiNzdjZS0wODE1LTQ1OTQtYmFmYS1kZWUzODEwODA5MWYiLCJhdWQiOiIxcnY3aWlqbGNndjRjb3J0aW5hMzIybnRyaSIsImV2ZW50X2lkIjoiMWNmZjA0OTUtNzdjNS00M2EyLTg2NDktMzA2ZGIwNjU3ZDA5IiwidG9rZW5fdXNlIjoiaWQiLCJhdXRoX3RpbWUiOjE3NDM3NjY5NjYsInBob25lX251bWJlciI6IisxNTYxNzg1NTY2OSIsImV4cCI6MTc0NDg3MDE0NiwiaWF0IjoxNzQ0ODY2NTQ2LCJmYW1pbHlfbmFtZSI6IkhlaWR0bWFubiIsImp0aSI6ImFkMDMxY2IwLWM2YjgtNGRlMS1hY2RlLTA3YTIyMzVmNThlYSIsImVtYWlsIjoiVHJveWhlaWR0bWFubkBpY2xvdWQuY29tIn0.PPfeD-o-zeZiLhVxsUXBhRZanQ5z58_hwTEMFQ3YUwhRDKw3RVD5V4cWZmM7ZY8T_8JRmmND3pKkWz-VZza_DlFSahyTtk1C0RgK5QsluDiMpbc5FJ2NwHCuclZVqLP26addiZZ4ONBzZb3hOYGCwupUVGUFVXbQ9a3XnbKeAP5PsQhP_17t-Whzpj0CLZxCYxkpgX_S4LXtlli2sc7Y1hJfkgjo50A4ijJIajh2WCk5l3P8dy0-qZPH1K868MUDp_RxKhvgwRQQt0p4fK4sIF3PDsNrzVL3cSjfQguw4VR9rjPU815hcyWLwEaYoxFURL3tL1q15pbaTDMvry_Sgg")
        }
    }
}

/// SwiftUI preview provider for TroyView
#Preview {
    TroyView()
} 