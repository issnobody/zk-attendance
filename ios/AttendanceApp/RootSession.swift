import Foundation
import Combine

final class RootSession: ObservableObject {
    enum Role {
        case none
        case student
        case admin
    }

    @Published var role: Role = .none
    @Published var errorMessage: String?

    // child sessions for student and admin flows
    let student = SessionStore()
    let admin   = AdminSessionStore()

    func login(username: String, password: String) {
        // First try admin login
        admin.login(username: username, password: password) { success in
            if success {
                DispatchQueue.main.async {
                    self.role = .admin
                }
            } else {
                // attempt student login
                self.admin.errorMessage = nil
                self.student.login(username: username, password: password) { ok in
                    DispatchQueue.main.async {
                        if ok {
                            self.role = .student
                        } else {
                            self.errorMessage = self.student.errorMessage
                        }
                    }
                }
            }
        }
    }

    func logout() {
        student.logout()
        admin.logout()
        role = .none
    }
}
