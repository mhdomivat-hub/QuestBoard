import Vapor

struct SCMDBImportRequestDTO: Content {
    let sourceBaseURL: String?
    let dryRun: Bool?
    let sourceMode: String?
    let updateSnapshot: Bool?
    let snapshotFile: File?
}

struct SCMDBImportPreviewItemDTO: Content {
    let section: String
    let name: String
}

struct SCMDBImportResultDTO: Content {
    let sourceBaseURL: String
    let version: String
    let sourceLabel: String
    let snapshotUpdated: Bool
    let totalDiscovered: Int
    let sectionCounts: [String: Int]
    let inserted: Int
    let skipped: Int
    let preview: [SCMDBImportPreviewItemDTO]
}