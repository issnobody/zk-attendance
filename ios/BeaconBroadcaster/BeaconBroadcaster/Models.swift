import Foundation

/// A student account
struct Student: Identifiable, Codable {
    let id: UUID
    let username: String
}

/// A timestamped attendance decision

