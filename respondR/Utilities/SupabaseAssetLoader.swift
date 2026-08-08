import Foundation
import Supabase

struct SupabaseConfig {
    static let projectUrlString = "https://ikswhcyfnqipzakncruf.supabase.co"
    static let bucketName = "assets"
}

struct SupabaseAssetLoader {

    static func downloadAllUSDZAssets() async throws {

        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_KEY") as? String else {
            throw NSError(
               domain: "Supabase",
               code: 1,
               userInfo: [
                   NSLocalizedDescriptionKey:
                       "SUPABASE_KEY not found in Info.plist"
               ]
           )
        }

        let client = SupabaseClient(
            supabaseURL: URL(string: SupabaseConfig.projectUrlString)!,
            supabaseKey: apiKey,
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

        let fileManager = FileManager.default
        let itemsURL = URL(fileURLWithPath: "items", isDirectory: true)
        if !fileManager.fileExists(atPath: itemsURL.path) {
            try fileManager.createDirectory(at: itemsURL, withIntermediateDirectories: true)
        }

        for file in files where file.name.lowercased().hasSuffix(".usdz") {
            let data = try await client.storage.from(SupabaseConfig.bucketName).download(path: file.name)
            print("Downloaded: \(file.name)")
            let fileURL = itemsURL.appendingPathComponent(file.name)

            try data.write(to: fileURL)
            print("Saved: \(fileURL.path)")
        }
    }
}
