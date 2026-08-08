import Foundation
import Supabase

struct SupabaseConfig {
    static let projectUrlString = "https://ikswhcyfnqipzakncruf.supabase.co"
    static let bucketName = "assets"

    static var apiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_KEY") as? String
    }

    static var storageBaseURL: URL {
        guard let url = URL(string: projectUrlString) else {
            fatalError("Supabase project URL is invalid. Update SupabaseConfig.projectUrlString with your project URL.")
        }
        return url.appendingPathComponent("storage/v1/object/public/")
            .appendingPathComponent(bucketName)
    }
}

struct SupabaseAssetLoader {
    static func downloadAllUSDZAssets() async throws -> [String: Data] {
        let client = SupabaseClient(
            supabaseURL: URL(string: SupabaseConfig.projectUrlString)!,
            supabaseKey: SupabaseConfig.apiKey,
            options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
        )

        let files = try await client.storage
            .from(SupabaseConfig.bucketName)
            .list(
                path: "folder",
                options: SearchOptions(
                    limit: 10,
                    offset: 0,
                    sortBy: SortBy(column: "name", order: "asc")
                )
            )

        var downloadedAssets: [String: Data] = [:]
        for file in files where file.name.lowercased().hasSuffix(".usdz") {
            downloadedAssets[file.name] = try await client.storage.from(SupabaseConfig.bucketName).download(path: file.name)
        }

        return downloadedAssets
    }
}
