import Vapor

struct SCMDBImportRequestDTO: Content {
    let sourceBaseURL: String?
    let dryRun: Bool?
}

struct SCMDBImportPreviewItemDTO: Content {
    let section: String
    let name: String
}

struct SCMDBImportResultDTO: Content {
    let sourceBaseURL: String
    let version: String
    let totalDiscovered: Int
    let sectionCounts: [String: Int]
    let inserted: Int
    let skipped: Int
    let preview: [SCMDBImportPreviewItemDTO]
}
