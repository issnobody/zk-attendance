// AttendanceRecord.swift

import Foundation

struct AttendanceRecord: Identifiable, Decodable {
  let user:   String?    // matches the JSON "user"
  let date:   Date       // matches the JSON "date"
  let status: String     // matches the JSON "status"

  // Make `id` something predictable — here we just reuse the timestamp
  // as a unique identifier for the list view.
  var id: Date { date }
}
