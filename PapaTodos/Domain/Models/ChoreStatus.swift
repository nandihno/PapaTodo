/// Mirrors the `status` check constraint on `public.chores` (pending | in_progress | done).
nonisolated enum ChoreStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case inProgress = "in_progress"
    case done
}
