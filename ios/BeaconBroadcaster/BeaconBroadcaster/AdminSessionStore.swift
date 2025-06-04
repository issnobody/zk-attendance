// AdminSessionStore.swift

import Foundation
import Combine

/// The shape of the /me response
private struct MeResponse: Decodable {
  let id: String
  let username: String
  let role: String
}

/// Model for a user as returned by GET /users
struct AdminUser: Identifiable, Codable {
    let id: String
    let username: String
}

/// Model for a single attendance record as returned by GET /attendance
struct AttendanceRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let status: String

    enum CodingKeys: String, CodingKey {
        case date, status
    }

    // Assign a fresh UUID locally
    init(id: UUID = UUID(), date: Date, status: String) {
        self.id = id
        self.date = date
        self.status = status
    }

    // Decode date & status, then generate an id
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let date   = try c.decode(Date.self,   forKey: .date)
        let status = try c.decode(String.self, forKey: .status)
        self.init(date: date, status: status)
    }
}

final class AdminSessionStore: ObservableObject {
    // MARK: — published state —
    @Published var isLoggedIn      = false
    @Published var token: String?  = nil
    @Published var errorMessage: String?

    @Published var users: [AdminUser]             = []
    @Published var selectedHistory: [AttendanceRecord] = []

    /// Your API’s base URL
    let baseURL: URL

    init(baseURL: URL = URL(string: "http://192.168.100.88:5100")!) {
        self.baseURL = baseURL
    }

    // MARK: — ADMIN LOGIN —

    func login(username: String, password: String, completion: @escaping(Bool)->Void) {
        let url = baseURL.appendingPathComponent("/login")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField:"Content-Type")
        req.httpBody = try? JSONEncoder().encode(
          ["username": username, "password": password]
        )

        URLSession.shared.dataTask(with: req) { data, _, err in
          DispatchQueue.main.async {
            if let err = err {
              self.errorMessage = err.localizedDescription
              return completion(false)
            }
            guard
              let data = data,
              let json = try? JSONDecoder().decode([String:String].self, from: data),
              let token = json["token"]
            else {
              self.errorMessage = "Invalid login response"
              return completion(false)
            }

            // store token, then call /me
            self.token = token
            self.fetchMe(completion: completion)
          }
        }.resume()
      }

      private func fetchMe(completion: @escaping(Bool)->Void) {
        guard let token = token else { return completion(false) }
        var req = URLRequest(url: baseURL.appendingPathComponent("/me"))
        req.setValue("Bearer \(token)", forHTTPHeaderField:"Authorization")

        URLSession.shared.dataTask(with: req) { data, _, err in
          DispatchQueue.main.async {
            if let err = err {
              self.errorMessage = err.localizedDescription
              self.token = nil
              return completion(false)
            }
            guard let data = data,
                  let me = try? JSONDecoder().decode(MeResponse.self, from: data)
            else {
              self.errorMessage = "Login Failed"
              self.token = nil
              return completion(false)
            }

            if me.role != "admin" {
              self.errorMessage = "Not an admin account"
              self.token = nil
              completion(false)
            } else {
              self.errorMessage = nil
              self.isLoggedIn = true
              self.fetchUsers()
              completion(true)
            }
          }
        }.resume()
      }

    // MARK: — FETCH ALL USERS —

    func fetchUsers() {
        guard let jwt = token else { return }
        let url = baseURL.appendingPathComponent("/users")
        var req = URLRequest(url: url)
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        

        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                if let err = err {
                    self.errorMessage = "Users load error: \(err.localizedDescription)"
                    return
                }
                guard let data = data else {
                    self.errorMessage = "No data loading users"
                    return
                }
                do {
                    self.users = try JSONDecoder().decode([AdminUser].self, from: data)
                    self.errorMessage = nil
                } catch {
                    self.errorMessage = "Users JSON error: \(error)"
                }
            }
        }.resume()
    }

    // MARK: — FETCH ONE USER’S HISTORY —

    /// Appends `?userId=…` to your /attendance endpoint.
    /// Fetch attendance history for *one* user by their id
    func fetchHistory(for user: AdminUser) {
        guard let token = token else { return }
        // build URL: GET /attendance?userId=...
        let url = baseURL
                       .appendingPathComponent("users")
                       .appendingPathComponent(user.id)
                       .appendingPathComponent("attendance")
         var req = URLRequest(url: url)
         req.httpMethod = "GET"
         req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, _, err in
          DispatchQueue.main.async {
            if let err = err {
              self.errorMessage = "History load error: \(err.localizedDescription)"
              return
            }
            guard let data = data else {
              self.errorMessage = "No data loading history"
              return
            }
            // debug print the raw JSON
            if let s = String(data: data, encoding: .utf8) {
              print("📥 /attendance raw JSON:", s)
            }

            let decoder = JSONDecoder()
            // make sure your server emits full‐ISO8601 with fractional seconds
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            decoder.dateDecodingStrategy = .custom { decoder in
              let c = try decoder.singleValueContainer()
              let str = try c.decode(String.self)
              if let d = iso.date(from: str) { return d }
              throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Cannot parse date: \(str)"
              )
            }

            do {
              self.selectedHistory = try decoder.decode(
                [AttendanceRecord].self, from: data
              )
              self.errorMessage = nil
            } catch {
              self.errorMessage = "History JSON error: \(error)"
            }
          }
        }.resume()
    }
}
private extension URL {
  func appending(_ name: String, value: String) -> URL {
    guard var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
      return self
    }
    var items = comps.queryItems ?? []
    items.append(.init(name: name, value: value))
    comps.queryItems = items
    return comps.url ?? self
  }
}

