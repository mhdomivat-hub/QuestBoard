import Vapor

struct RetentionSelectionCleanupRequestDTO: Content {
    let dryRun: Bool?
    let targets: [String]
}

struct RetentionSelectionCleanupTargetResultDTO: Content {
    let key: String
    let label: String
    let candidateCount: Int
    let deletedCount: Int
}

struct RetentionSelectionCleanupResponseDTO: Content {
    let dryRun: Bool
    let targets: [RetentionSelectionCleanupTargetResultDTO]
    let totalCandidateCount: Int
    let totalDeletedCount: Int
}
