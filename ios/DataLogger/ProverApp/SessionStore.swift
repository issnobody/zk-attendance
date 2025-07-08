import Foundation
import Combine

final class SessionStore: ObservableObject {
  @Published var isLoggedIn   = false
  @Published var username: String?
  @Published var token: String?
  @Published var errorMessage: String?

  @Published var history: [AttendanceRecord] = []
    func addRecord(_ record: AttendanceRecord) {
        history.append(record)
      }
    

  private let baseURL = URL(string: "http://192.168.100.226:5100")!

  // MARK: Sign up
  func signup(username: String, password: String, completion: @escaping(Bool)->Void) {
    var req = URLRequest(url: baseURL.appendingPathComponent("/signup"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField:"Content-Type")
    req.httpBody = try? JSONEncoder().encode(
        ["username": username, "password": password]
    )
    URLSession.shared.dataTask(with: req) { data,_,err in
      DispatchQueue.main.async {
        if let err = err {
          self.errorMessage = err.localizedDescription; completion(false)
        }
        else { completion(true) }
      }
    }.resume()
  }

  // MARK: Log in
  func login(username: String, password: String, completion: @escaping(Bool)->Void) {
    var req = URLRequest(url: baseURL.appendingPathComponent("/login"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField:"Content-Type")
    req.httpBody = try? JSONEncoder().encode(
        ["username": username, "password": password]
    )
    
    URLSession.shared.dataTask(with: req) { data,_,err in
      DispatchQueue.main.async {
          
        if let err = err {
          self.errorMessage = err.localizedDescription; return completion(false)
        }
          
        guard
          let data = data,
          
          let json = try? JSONDecoder().decode([String:String].self, from: data),
          let token = json["token"]
        else {
          self.errorMessage = "Bad login response"; return completion(false)
        }
        self.token      = token
        self.username   = username
        self.isLoggedIn = true
        self.fetchHistory()
        completion(true)
      }
    }.resume()
  }
    
 
       func recordAttendance(status: String) {
           guard let token = token else { return }
           let url = baseURL.appendingPathComponent("/attendance")
           var req = URLRequest(url: url)
           req.httpMethod = "POST"
           req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
           req.setValue("application/json", forHTTPHeaderField: "Content-Type")
           req.httpBody = try? JSONEncoder().encode(["status": status])

           URLSession.shared.dataTask(with: req) { _, _, error in
               DispatchQueue.main.async {
                   if let e = error {
                       self.errorMessage = "Save error: \(e.localizedDescription)"
                   } else {
                       // refetch the up-to-date history
                       self.fetchHistory()
                   }
               }
           }.resume()
       }



    func fetchHistory() {
      guard let token = self.token else { return }
      var req = URLRequest(url: baseURL.appendingPathComponent("/attendance"))
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

      URLSession.shared.dataTask(with: req) { data, _, error in
        if let error = error {
          print("⚠️ fetchHistory network error:", error)
          return
        }
        guard let data = data else {
          print("⚠️ fetchHistory: no data")
          return
        }
        if let jsonStr = String(data: data, encoding: .utf8) {
          print("📥 /attendance raw JSON:", jsonStr)
        }

        do {
          let decoder = JSONDecoder()
          let formatter = DateFormatter()
          formatter.locale = Locale(identifier: "en_US_POSIX")
          // This format accepts both "2025-05-06T05:18:46Z" and
          // "2025-05-06T05:18:46.707Z"
          formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
          decoder.dateDecodingStrategy = .formatted(formatter)

          let records = try decoder.decode([AttendanceRecord].self, from: data)
          DispatchQueue.main.async {
            self.history = records
          }
        } catch {
          print("⚠️ fetchHistory decoding error:", error)
        }
      }.resume()
    }



  func logout() {
    isLoggedIn = false
    token       = nil
    username    = nil
    history     = []
  }
}
