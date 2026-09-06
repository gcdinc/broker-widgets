import Foundation

struct AppSoftwareVersion: Equatable {
    let marketing: String
    let build: String
    let zipURL: URL

    static var local: AppSoftwareVersion {
        AppSoftwareVersion(
            marketing: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            zipURL: AppConstants.latestZipURL
        )
    }

    static func isNewer(_ remote: AppSoftwareVersion, than local: AppSoftwareVersion) -> Bool {
        let marketing = compareDotted(remote.marketing, local.marketing)
        if marketing != 0 { return marketing > 0 }
        return (Int(remote.build) ?? 0) > (Int(local.build) ?? 0)
    }

    static func compareDotted(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b ? 1 : -1 }
        }
        return 0
    }
}
