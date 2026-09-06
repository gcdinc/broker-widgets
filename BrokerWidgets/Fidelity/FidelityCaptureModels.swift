import Foundation

struct CookieRecord: Codable {
    var properties: [String: String]
}

struct CapturedPage: Decodable {
    var href: String
    var title: String?
    var hasPassword: Bool
    var captured: [CapturedNetwork]
    var text: String?
}

struct CapturedNetwork: Decodable {
    var url: String?
    var text: String?
}
