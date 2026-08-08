import Foundation
import Supabase

struct SupabaseConfig {
    static let projectUrlString = "https://ikswhcyfnqipzakncruf.supabase.co"
    static let bucketName = "assets"
}

struct SupabaseAssetLoader {

    static func downloadAllUSDZAssets() async throws -> [String] {

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
                options: SearchOptions(
                    limit: 10,
                    offset: 0,
                    sortBy: SortBy(column: "name", order: "asc")
                )
            )

        print("Found \(files.count) files in Supabase bucket '\(SupabaseConfig.bucketName)'.")
        for file in files {
            print("  \(file.name)")
        }

        let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let itemsURL = documentsURL.appendingPathComponent("items")

        try FileManager.default.createDirectory(
            at: itemsURL,
            withIntermediateDirectories: true
        )

        var downloadedAssetNames: [String] = []

        for file in files where file.name.lowercased().hasSuffix(".usdz") {
            let data = try await client.storage
                .from(SupabaseConfig.bucketName)
                .download(path: file.name)

            let destinationURL = itemsURL.appendingPathComponent(file.name)

            try data.write(
                to: destinationURL,
                options: .atomic
            )

            downloadedAssetNames.append(file.name)

            print("Downloaded \(file.name)")
            print("Saved to: \(destinationURL.path)")
        }

        return downloadedAssetNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
