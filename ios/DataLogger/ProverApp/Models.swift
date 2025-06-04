// Models.swift

import Foundation
import AnyCodable

/// The JSON we get back from POST /prove
struct ProveResponse: Codable {
  let proof: [String:AnyCodable]
  let publicSignals: [AnyCodable]
}

enum AttendanceStatus: String, Codable {
  case present
  case absent
  case leftBehind
  case outOfRange
}

