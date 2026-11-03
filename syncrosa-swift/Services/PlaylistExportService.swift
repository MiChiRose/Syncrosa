import Foundation
import CryptoKit
import Darwin

struct USBExportJobSummary: Identifiable {
    let id: UUID
    let playlistName: String
    let state: String
    let destinationName: String
    let completedCount: Int
    let totalCount: Int
    let createdAt: Date
    let journalURL: URL
    let lastError: String?
}

final class PlaylistExportService {
    static let shared = PlaylistExportService()
    static let jobsDidChangeNotification = Notification.Name("SyncrosaUSBExportJobsDidChange")

    struct TrackFile: Codable, Equatable {
        let name: String
        let artist: String
        var filePath: String
        let fileSize: Int64
        let isDRM: Bool
        var persistentID: String? = nil
        var bookmarkData: Data? = nil
    }
    struct ExportProgress {
        let currentTrack: Int
        let totalTracks: Int
        let currentTrackName: String
        let bytesCopied: Int64
        let totalBytes: Int64
    }
    enum ExportMode: String, Codable { case all, fitAvailable }
    struct ExportResult {
        var copiedCount = 0
        var existingCount = 0
        var skippedDRM = 0
        var skippedNotDownloaded = 0
        var skippedForSpace = 0
        var totalBytesCopied: Int64 = 0
        var remainingBytesToCopy: Int64 = 0
        var errors: [String] = []
        var wasCancelled = false
        var insufficientSpace = false
        var jobID: UUID? = nil
    }
    private struct Manifest: Codable {
        var schemaVersion = 1
        var folderID: String
        var entries: [ManifestEntry] = []
        var playlistFiles: [String: String]? = nil
    }
    private struct ManifestEntry: Codable, Equatable {
        let sourceKey: String
        let filename: String
        let size: Int64
        let sha256: String
    }
    private struct Entry: Codable, Equatable {
        let id: UUID
        var track: TrackFile
        var filename: String?
        var sha256: String?
        var size: Int64 = 0
        var selected = true
        var completed = false
        var temporaryName: String?
        var temporaryFileID: UInt64?
        var failureMessage: String?
    }
    private struct Job: Codable {
        var schemaVersion = 1
        let id: UUID
        let playlistName: String
        let createdAt: Date
        let destinationName: String
        let volumeID: String
        let rootFileID: UInt64
        let isVolumeRoot: Bool
        let folderName: String
        var folderID: String
        var folderPrepared = false
        var mode: ExportMode
        let createM3U: Bool
        let createM3U8: Bool
        let useIPodSafeNames: Bool
        var selectionFinalized = false
        var entries: [Entry]
        var state = "pending"
        var lastError: String?
        var skippedDRM = 0
        var skippedNotDownloaded = 0
        var skippedForSpace = 0
    }
    private struct Checkpoint: Codable {
        let schemaVersion: Int
        let jobID: UUID
        let sequence: Int
        let state: String
        let lastError: String?
        let folderID: String
        let folderPrepared: Bool
        let mode: ExportMode
        let selectionFinalized: Bool
        let skippedForSpace: Int
        let entries: [Entry]
    }
    private var checkpointCache: (job: Job, sequence: Int)?
    private var activeRootSignature: (path: String, inode: UInt64, isVolumeRoot: Bool, device: Int32)?
    private var activeFolderSignature: (path: String, inode: UInt64, device: Int32)?

    private enum Failure: LocalizedError {
        case message(String), cancelled
        var errorDescription: String? {
            switch self { case .message(let value): return value; case .cancelled: return "Export paused. It can be continued in Recovery Center." }
        }
    }

    private let journalDirectory: URL
    private let volumeIdentity: (URL) throws -> String
    private let availableCapacity: (URL) throws -> Int64
    private let fault: ((String, URL) throws -> Void)?
    private let lock = NSLock()
    private var running = false
    private var cancelled = false
    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    init(journalDirectory: URL = SyncrosaStorage.applicationSupportDirectory.appendingPathComponent("USB Export Jobs", isDirectory: true),
         volumeIdentity: @escaping (URL) throws -> String = PlaylistExportService.defaultVolumeIdentity,
         availableCapacity: @escaping (URL) throws -> Int64 = PlaylistExportService.defaultAvailableCapacity,
         fault: ((String, URL) throws -> Void)? = nil) {
        self.journalDirectory = journalDirectory
        self.volumeIdentity = volumeIdentity
        self.availableCapacity = availableCapacity
        self.fault = fault
    }

    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    private func start() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !running else { return false }
        running = true; cancelled = false
        notifyJobsChanged()
        return true
    }
    private func finish() { activeRootSignature = nil; activeFolderSignature = nil; lock.lock(); running = false; lock.unlock(); notifyJobsChanged() }
    private func notifyJobsChanged() { DispatchQueue.main.async { NotificationCenter.default.post(name: Self.jobsDidChangeNotification, object: self) } }
    private func checkCancellation() throws {
        lock.lock(); let stop = cancelled; lock.unlock()
        if stop { throw Failure.cancelled }
    }

    func exportToUSB(tracks: [TrackFile], destination: URL, playlistName: String, mode: ExportMode,
                     createM3U: Bool = false, createM3U8: Bool = false, useIPodSafeNames: Bool = false,
                     progress: @escaping (ExportProgress) -> Void, completion: @escaping (ExportResult) -> Void) {
        guard start() else { DispatchQueue.main.async { completion(ExportResult(errors: ["Another USB export is already running."])) }; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let scoped = destination.startAccessingSecurityScopedResource()
            defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
            let result = self.createAndRun(tracks: tracks, destination: destination, playlistName: playlistName, mode: mode, createM3U: createM3U, createM3U8: createM3U8, useIPodSafeNames: useIPodSafeNames) { value in DispatchQueue.main.async { progress(value) } }
            self.finish()
            DispatchQueue.main.async { completion(result) }
        }
    }

    func resume(jobID: UUID, destination: URL, mode: ExportMode? = nil,
                progress: @escaping (ExportProgress) -> Void, completion: @escaping (ExportResult) -> Void) {
        guard start() else { DispatchQueue.main.async { completion(ExportResult(errors: ["Another USB export is already running."])) }; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let scoped = destination.startAccessingSecurityScopedResource()
            defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
            let result = self.resumeRun(jobID: jobID, destination: destination, mode: mode) { value in DispatchQueue.main.async { progress(value) } }
            self.finish()
            DispatchQueue.main.async { completion(result) }
        }
    }

    // The same engine is exercised by offline tests using ordinary temporary folders.
    func exportSynchronously(tracks: [TrackFile], destination: URL, playlistName: String, mode: ExportMode = .all,
                             createM3U: Bool = false, createM3U8: Bool = false, useIPodSafeNames: Bool = false,
                             progress: (ExportProgress) -> Void = { _ in }) -> ExportResult {
        guard start() else { return ExportResult(errors: ["Another USB export is already running."]) }
        defer { finish() }
        return createAndRun(tracks: tracks, destination: destination, playlistName: playlistName, mode: mode, createM3U: createM3U, createM3U8: createM3U8, useIPodSafeNames: useIPodSafeNames, progress: progress)
    }
    func resumeSynchronously(jobID: UUID, destination: URL, mode: ExportMode? = nil, progress: (ExportProgress) -> Void = { _ in }) -> ExportResult {
        guard start() else { return ExportResult(errors: ["Another USB export is already running."]) }
        defer { finish() }
        return resumeRun(jobID: jobID, destination: destination, mode: mode, progress: progress)
    }

    func loadPendingJobs() -> (jobs: [USBExportJobSummary], errors: [String]) {
        guard FileManager.default.fileExists(atPath: journalDirectory.path) else { return ([], []) }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: journalDirectory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("swift-") && $0.pathExtension == "json" }
            var jobs: [USBExportJobSummary] = []; var errors: [String] = []
            for file in files {
                do {
                    let job = try readJob(file)
                    if job.state != "completed" {
                        jobs.append(USBExportJobSummary(id: job.id, playlistName: job.playlistName, state: job.state, destinationName: job.destinationName, completedCount: job.entries.filter { $0.selected && $0.completed }.count, totalCount: job.entries.filter(\.selected).count, createdAt: job.createdAt, journalURL: file, lastError: job.lastError))
                    }
                } catch { errors.append("\(file.lastPathComponent): \(error.localizedDescription)") }
            }
            return (jobs.sorted { $0.createdAt > $1.createdAt }, errors)
        } catch { return ([], [error.localizedDescription]) }
    }
    func discardJob(_ id: UUID) throws {
        guard !isRunning else { throw Failure.message("Wait for the current export before discarding a recovery record.") }
        let file = journalURL(id)
        _ = try readJob(file)
        let checkpoints = file.appendingPathExtension("checkpoints")
        if FileManager.default.fileExists(atPath: checkpoints.path) {
            guard !isSymlink(checkpoints) else { throw Failure.message("Recovery checkpoints cannot be symbolic links.") }
            try FileManager.default.removeItem(at: checkpoints)
        }
        try FileManager.default.removeItem(at: file)
        notifyJobsChanged()
    }

    private func createAndRun(tracks: [TrackFile], destination: URL, playlistName: String, mode: ExportMode,
                              createM3U: Bool, createM3U8: Bool, useIPodSafeNames: Bool, progress: (ExportProgress) -> Void) -> ExportResult {
        do {
            let root = destination.resolvingSymlinksInPath().standardizedFileURL
            let identity = try volumeIdentity(root)
            try validateRoot(root, identity: identity)
            let signature = try rootSignature(root)
            var job = Job(id: UUID(), playlistName: playlistName, createdAt: Date(), destinationName: destination.lastPathComponent,
                          volumeID: identity, rootFileID: signature.inode, isVolumeRoot: signature.isVolumeRoot, folderName: sanitizedFolderName(playlistName), folderID: UUID().uuidString,
                          mode: mode, createM3U: createM3U, createM3U8: createM3U8, useIPodSafeNames: useIPodSafeNames,
                          entries: tracks.filter { !$0.isDRM }.map { track in
                              var captured = track
                              captured.bookmarkData = try? URL(fileURLWithPath: track.filePath).bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
                              return Entry(id: UUID(), track: captured)
                          })
            job.skippedDRM = tracks.filter(\.isDRM).count
            try saveJob(job)
            return run(&job, root: root, progress: progress)
        } catch { return ExportResult(errors: [error.localizedDescription]) }
    }
    private func resumeRun(jobID: UUID, destination: URL, mode: ExportMode?, progress: (ExportProgress) -> Void) -> ExportResult {
        do {
            var job = try readJob(journalURL(jobID))
            guard job.id == jobID else { throw Failure.message("Recovery record ID does not match its filename.") }
            guard job.state != "completed" else { throw Failure.message("This export is already complete.") }
            if let mode, !job.selectionFinalized { job.mode = mode }
            return run(&job, root: destination.resolvingSymlinksInPath().standardizedFileURL, progress: progress)
        } catch { return ExportResult(errors: [error.localizedDescription], jobID: jobID) }
    }

    private func run(_ job: inout Job, root: URL, progress: (ExportProgress) -> Void) -> ExportResult {
        var result = ExportResult(skippedDRM: job.skippedDRM, jobID: job.id)
        var manifest: Manifest?
        var folder: URL?
        var folderLock: Int32 = -1
        var sourceScopes: [URL] = []
        defer { sourceScopes.forEach { $0.stopAccessingSecurityScopedResource() } }
        defer { if folderLock >= 0 { _ = flock(folderLock, LOCK_UN); close(folderLock) } }
        do {
            var initialRoot = stat(); guard lstat(root.path, &initialRoot) == 0 else { throw posixError("The selected drive is unavailable") }
            activeRootSignature = (root.path, job.rootFileID, job.isVolumeRoot, initialRoot.st_dev)
            try validateRoot(root, identity: job.volumeID)
            guard safeLeaf(job.folderName) else { throw Failure.message("Unsafe export folder in the recovery record.") }
            let exportFolder = root.appendingPathComponent(job.folderName, isDirectory: true)
            folder = exportFolder
            if !FileManager.default.fileExists(atPath: exportFolder.path) {
                guard !job.folderPrepared else { throw Failure.message("The original export folder is missing. Select the original drive.") }
                try validateRoot(root, identity: job.volumeID)
                try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: false)
            }
            try validateFolder(exportFolder, root: root, identity: job.volumeID)
            var folderInfo = stat(); guard lstat(exportFolder.path, &folderInfo) == 0 else { throw posixError("Could not identify the export folder") }
            activeFolderSignature = (exportFolder.path, UInt64(folderInfo.st_ino), folderInfo.st_dev)
            folderLock = try acquireFolderLock(exportFolder)
            let manifestURL = exportFolder.appendingPathComponent(".syncrosa-export.json")
            if FileManager.default.fileExists(atPath: manifestURL.path) || isSymlink(manifestURL) {
                let loaded = try readManifest(manifestURL)
                if job.folderPrepared && loaded.folderID != job.folderID { throw Failure.message("This is not the original export folder. Select the original drive and folder.") }
                job.folderID = loaded.folderID
                manifest = loaded
            } else {
                guard !job.folderPrepared else { throw Failure.message("The export manifest is missing. It must be restored before this job can continue.") }
                manifest = Manifest(folderID: job.folderID)
                try saveManifest(manifest!, in: exportFolder, root: root, identity: job.volumeID)
            }
            job.folderPrepared = true; job.state = "checking"; job.lastError = nil
            try saveJob(job)
            for index in job.entries.indices where job.entries[index].selected {
                job.entries[index].completed = false; job.entries[index].failureMessage = nil
                if let bookmark = job.entries[index].track.bookmarkData {
                    var stale = false
                    if let source = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) {
                        if source.startAccessingSecurityScopedResource() { sourceScopes.append(source) }
                        job.entries[index].track.filePath = source.path
                        if stale { job.entries[index].track.bookmarkData = try? source.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) }
                    }
                }
            }
            var plannedCopies: [String: String] = [:]
            var reserved = Set<String>()
            var needed: Int64 = 0
            var reusable = Set<Int>()
            // Recheck both source and destination even for entries completed before a crash.
            for index in job.entries.indices {
                try checkCancellation()
                if job.selectionFinalized && !job.entries[index].selected { continue }
                let track = job.entries[index].track
                progress(ExportProgress(currentTrack: index + 1, totalTracks: job.entries.count, currentTrackName: "Checking: \(track.artist) - \(track.name)", bytesCopied: 0, totalBytes: 0))
                do {
                try cleanupTemporary(&job.entries[index], in: exportFolder, root: root, identity: job.volumeID)
                let source = URL(fileURLWithPath: track.filePath)
                let fingerprint = try hashFile(source, root: root, identity: job.volumeID)
                job.entries[index].sha256 = fingerprint.hash
                job.entries[index].size = fingerprint.size
                let base = filename(for: track, safe: job.useIPodSafeNames)
                let previous = manifest!.entries.filter { $0.sourceKey == sourceKey(track) }.map(\.filename)
                let exact = job.entries[index].filename.map { [$0] } ?? []
                let names = try candidateNames(base: base, folder: exportFolder, preferred: exact + previous, safe: job.useIPodSafeNames)
                var found: String?
                for name in names {
                    let target = exportFolder.appendingPathComponent(name)
                    guard (try? regularSize(target)) == fingerprint.size else { continue }
                    if try hashFile(target, root: root, identity: job.volumeID).hash == fingerprint.hash { found = name; break }
                }
                if let found {
                    job.entries[index].filename = found; job.entries[index].completed = true
                    reusable.insert(index); reserved.insert(found.lowercased())
                    updateManifest(&manifest!, entry: job.entries[index])
                } else {
                    job.entries[index].completed = false
                    let copyKey = sourceKey(track) + ":" + fingerprint.hash
                    let destination = plannedCopies[copyKey] ?? uniqueName(base, folder: exportFolder, reserved: reserved)
                    plannedCopies[copyKey] = destination
                    job.entries[index].filename = destination; reserved.insert(destination.lowercased())
                }
                } catch {
                    try checkCancellation()
                    try validateRoot(root, identity: job.volumeID)
                    job.entries[index].completed = false
                    job.entries[index].failureMessage = error.localizedDescription
                    result.skippedNotDownloaded += 1
                    if result.errors.count < 25 { result.errors.append("\(track.artist) - \(track.name): \(error.localizedDescription)") }
                }
            }
            try saveManifest(manifest!, in: exportFolder, root: root, identity: job.volumeID)
            needed = neededBytes(job)
            result.remainingBytesToCopy = needed
            let capacity = try availableCapacity(root)
            if !job.selectionFinalized && job.mode == .fitAvailable {
                var remaining = max(0, capacity)
                for index in job.entries.indices { job.entries[index].selected = reusable.contains(index) || job.entries[index].failureMessage != nil }
                let groups = Dictionary(grouping: job.entries.indices.filter { !reusable.contains($0) && job.entries[$0].failureMessage == nil }) { job.entries[$0].filename ?? "" }
                for group in groups.values.shuffled() {
                    let size = job.entries[group[0]].size
                    if size <= remaining { for index in group { job.entries[index].selected = true }; remaining -= size }
                }
                job.skippedForSpace = job.entries.filter { !$0.selected }.count
                needed = capacity - remaining
            } else if needed > capacity {
                job.state = "needs-space"; job.lastError = "Not enough free space for the remaining files."
                result.insufficientSpace = true
                throw Failure.message(job.lastError!)
            }
            job.selectionFinalized = true; job.state = "copying"
            try saveJob(job)
            let selected = job.entries.indices.filter { job.entries[$0].selected }
            let totalBytes = neededBytes(job)
            result.existingCount = selected.filter { reusable.contains($0) }.count
            result.skippedForSpace = job.skippedForSpace
            for (position, index) in selected.enumerated() {
                try checkCancellation()
                guard !job.entries[index].completed, job.entries[index].failureMessage == nil else { continue }
                try validateFolder(exportFolder, root: root, identity: job.volumeID)
                let entry = job.entries[index]
                guard let filename = entry.filename, safeLeaf(filename), let expectedHash = entry.sha256 else { throw Failure.message("Incomplete recovery entry.") }
                let sharedTarget = exportFolder.appendingPathComponent(filename)
                if (try? regularSize(sharedTarget)) == entry.size, try hashFile(sharedTarget, root: root, identity: job.volumeID).hash == expectedHash {
                    job.entries[index].completed = true
                    updateManifest(&manifest!, entry: job.entries[index])
                    try saveJob(job)
                    continue
                }
                let temporary = ".syncrosa-\(job.id.uuidString)-\(entry.id.uuidString)-\(UUID().uuidString).part"
                job.entries[index].temporaryName = temporary; job.entries[index].temporaryFileID = nil
                try saveJob(job)
                let temporaryURL = exportFolder.appendingPathComponent(temporary)
                let descriptor = open(temporaryURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
                guard descriptor >= 0 else { throw posixError("Could not create a temporary export file") }
                let writer = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                do {
                    var metadata = stat(); fstat(descriptor, &metadata)
                    job.entries[index].temporaryFileID = UInt64(metadata.st_ino)
                    try saveJob(job)
                    let reader = try openReader(URL(fileURLWithPath: entry.track.filePath))
                    defer { try? reader.close() }
                    var hasher = SHA256(); var length: Int64 = 0
                    while let data = try reader.read(upToCount: 1024 * 1024), !data.isEmpty {
                        try checkCancellation(); try validateFolder(exportFolder, root: root, identity: job.volumeID)
                        try writer.write(contentsOf: data); hasher.update(data: data); length += Int64(data.count)
                        result.totalBytesCopied += Int64(data.count)
                        progress(ExportProgress(currentTrack: position + 1, totalTracks: selected.count, currentTrackName: "\(entry.track.artist) - \(entry.track.name)", bytesCopied: result.totalBytesCopied, totalBytes: totalBytes))
                        try fault?("afterChunk", temporaryURL)
                    }
                    try writer.synchronize(); try writer.close()
                    let copiedHash = hex(hasher.finalize())
                    guard length == entry.size, copiedHash == expectedHash else { throw Failure.message("The source changed during copying. Continue the job to check it again.") }
                    let verified = try hashFile(temporaryURL, root: root, identity: job.volumeID)
                    guard verified.hash == expectedHash, verified.size == length else { throw Failure.message("The copied file did not pass verification.") }
                    try checkCancellation(); try validateFolder(exportFolder, root: root, identity: job.volumeID)
                    let finalURL = exportFolder.appendingPathComponent(filename)
                    guard renamex_np(temporaryURL.path, finalURL.path, UInt32(RENAME_EXCL)) == 0 else { throw posixError("Could not safely finish the export file") }
                    try fault?("afterPromotion", finalURL)
                    job.entries[index].completed = true; job.entries[index].temporaryName = nil; job.entries[index].temporaryFileID = nil
                    result.copiedCount += 1
                    updateManifest(&manifest!, entry: job.entries[index])
                    try saveJob(job)
                } catch { try? writer.close(); throw error }
            }
            try writePlaylistFiles(job: job, manifest: &manifest!, folder: exportFolder, root: root)
            try saveManifest(manifest!, in: exportFolder, root: root, identity: job.volumeID)
            let unfinished = job.entries.contains { $0.selected && !$0.completed }
            job.state = unfinished ? "interrupted" : "completed"
            job.lastError = unfinished ? result.errors.prefix(3).joined(separator: "\n") : nil
            try saveJob(job)
        } catch {
            result.wasCancelled = (error as? Failure).map { if case .cancelled = $0 { return true }; return false } ?? false
            if !result.wasCancelled { result.errors.append(error.localizedDescription) }
            job.state = result.insufficientSpace ? "needs-space" : (result.wasCancelled ? "paused" : "interrupted")
            job.lastError = error.localizedDescription
            if let folder, (try? validateFolder(folder, root: root, identity: job.volumeID)) != nil {
                for index in job.entries.indices { try? cleanupTemporary(&job.entries[index], in: folder, root: root, identity: job.volumeID) }
                if manifest != nil {
                    do {
                        // Completed files remain useful after cancellation; never reference a .part file.
                        try writePlaylistFiles(job: job, manifest: &manifest!, folder: folder, root: root)
                        try saveManifest(manifest!, in: folder, root: root, identity: job.volumeID)
                    } catch { result.errors.append("Playlist checkpoint: \(error.localizedDescription)") }
                }
            }
            do { try saveJob(job) } catch { result.errors.append("Recovery record: \(error.localizedDescription)") }
        }
        result.skippedForSpace = job.skippedForSpace
        result.existingCount = job.entries.filter { $0.selected && $0.completed }.count - result.copiedCount
        return result
    }

    private func neededBytes(_ job: Job) -> Int64 {
        var names = Set<String>()
        return job.entries.filter { $0.selected && !$0.completed && $0.failureMessage == nil }.reduce(Int64(0)) { result, entry in
            guard let name = entry.filename, names.insert(name.lowercased()).inserted else { return result }
            return result + entry.size
        }
    }

    private func journalURL(_ id: UUID) -> URL { journalDirectory.appendingPathComponent("swift-\(id.uuidString).json") }
    private func saveJob(_ job: Job) throws {
        var committed = false
        defer { if !committed { checkpointCache = nil } }
        try FileManager.default.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        let file = journalURL(job.id)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        if !FileManager.default.fileExists(atPath: file.path) {
            try encoder.encode(job).write(to: file, options: .atomic)
            checkpointCache = (job, 0)
            committed = true
            return
        }
        let prior: (job: Job, sequence: Int)
        if let cache = checkpointCache, cache.job.id == job.id { prior = cache }
        else { prior = try readJobAndSequence(file) }
        let previous = Dictionary(uniqueKeysWithValues: prior.job.entries.map { ($0.id, $0) })
        let changed = job.entries.filter { previous[$0.id] != $0 }
        let event = Checkpoint(schemaVersion: 1, jobID: job.id, sequence: prior.sequence + 1,
            state: job.state, lastError: job.lastError, folderID: job.folderID, folderPrepared: job.folderPrepared,
            mode: job.mode, selectionFinalized: job.selectionFinalized, skippedForSpace: job.skippedForSpace, entries: changed)
        let path = file.appendingPathExtension("checkpoints")
        guard !isSymlink(path) else { throw Failure.message("Recovery checkpoints cannot be symbolic links.") }
        let descriptor = open(path.path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw posixError("Could not open the recovery checkpoint") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        // Scan backwards only when the last append was torn; normal checkpoints
        // append a small delta without reading the growing log again.
        if length > 0 {
            try handle.seek(toOffset: length - 1)
            if try handle.read(upToCount: 1) != Data([10]) {
                var cursor = length
                var completeLength: UInt64 = 0
                while cursor > 0 {
                    let start = cursor > 65536 ? cursor - 65536 : 0
                    try handle.seek(toOffset: start)
                    let block = try handle.read(upToCount: Int(cursor - start)) ?? Data()
                    if let newline = block.lastIndex(of: 10) { completeLength = start + UInt64(newline) + 1; break }
                    cursor = start
                }
                try handle.truncate(atOffset: completeLength)
            }
        }
        try handle.seekToEnd()
        var data = try encoder.encode(event); data.append(10)
        try handle.write(contentsOf: data); try handle.synchronize()
        checkpointCache = (job, event.sequence)
        committed = true
    }
    private func readJob(_ url: URL) throws -> Job { try readJobAndSequence(url).job }
    private func readJobAndSequence(_ url: URL) throws -> (job: Job, sequence: Int) {
        guard !isSymlink(url) else { throw Failure.message("Recovery records cannot be symbolic links.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var job = try decoder.decode(Job.self, from: Data(contentsOf: url))
        guard url.lastPathComponent == "swift-\(job.id.uuidString).json" else { throw Failure.message("Recovery record ID does not match its filename.") }
        guard Set(job.entries.map(\.id)).count == job.entries.count else { throw Failure.message("Duplicate recovery entry identifiers.") }
        let indices = Dictionary(uniqueKeysWithValues: job.entries.enumerated().map { ($0.element.id, $0.offset) })
        var sequence = 0
        let checkpointURL = url.appendingPathExtension("checkpoints")
        if FileManager.default.fileExists(atPath: checkpointURL.path) || isSymlink(checkpointURL) {
            guard !isSymlink(checkpointURL) else { throw Failure.message("Recovery checkpoints cannot be symbolic links.") }
            let data = try Data(contentsOf: checkpointURL)
            if let end = data.lastIndex(of: 10) {
                for line in data.prefix(through: end).split(separator: 10, omittingEmptySubsequences: false).dropLast() {
                    let event = try decoder.decode(Checkpoint.self, from: Data(line))
                    guard event.schemaVersion == 1, event.jobID == job.id, event.sequence == sequence + 1 else { throw Failure.message("Invalid recovery checkpoint sequence.") }
                    for entry in event.entries {
                        guard let index = indices[entry.id] else { throw Failure.message("Unknown track in a recovery checkpoint.") }
                        job.entries[index] = entry
                    }
                    job.state = event.state; job.lastError = event.lastError; job.folderID = event.folderID
                    job.folderPrepared = event.folderPrepared; job.mode = event.mode
                    job.selectionFinalized = event.selectionFinalized; job.skippedForSpace = event.skippedForSpace
                    sequence = event.sequence
                }
            }
        }
        guard job.schemaVersion == 1, job.rootFileID > 0, safeLeaf(job.folderName), UUID(uuidString: job.folderID) != nil,
              job.entries.allSatisfy({ ($0.filename == nil || safeLeaf($0.filename!)) && ($0.temporaryName == nil || safeTemporary($0.temporaryName!, job: job.id, entry: $0.id)) }) else { throw Failure.message("Invalid or unsafe USB recovery record.") }
        return (job, sequence)
    }
    private func readManifest(_ url: URL) throws -> Manifest {
        guard !isSymlink(url) else { throw Failure.message("The export manifest cannot be a symbolic link.") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        guard manifest.schemaVersion == 1, UUID(uuidString: manifest.folderID) != nil,
              manifest.entries.allSatisfy({ safeLeaf($0.filename) && validHash($0.sha256) && $0.size >= 0 }),
              (manifest.playlistFiles ?? [:]).allSatisfy({ safeLeaf($0.key) && validHash($0.value) }) else { throw Failure.message("Invalid or unsafe export manifest. No music files were replaced.") }
        return manifest
    }
    private func saveManifest(_ manifest: Manifest, in folder: URL, root: URL, identity: String) throws {
        try validateFolder(folder, root: root, identity: identity)
        let target = folder.appendingPathComponent(".syncrosa-export.json")
        guard !isSymlink(target) else { throw Failure.message("The export manifest cannot be a symbolic link.") }
        if FileManager.default.fileExists(atPath: target.path) {
            let previous = try readManifest(target)
            let sort: (ManifestEntry, ManifestEntry) -> Bool = { left, right in
                if left.sourceKey != right.sourceKey { return left.sourceKey < right.sourceKey }
                if left.filename != right.filename { return left.filename < right.filename }
                return left.sha256 < right.sha256
            }
            if previous.folderID == manifest.folderID, previous.schemaVersion == manifest.schemaVersion,
               previous.entries.sorted(by: sort) == manifest.entries.sorted(by: sort),
               (previous.playlistFiles ?? [:]) == (manifest.playlistFiles ?? [:]) { return }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: target, options: .atomic)
    }
    private func updateManifest(_ manifest: inout Manifest, entry: Entry) {
        guard let filename = entry.filename, let hash = entry.sha256 else { return }
        let key = sourceKey(entry.track)
        manifest.entries.removeAll { $0.sourceKey == key }
        manifest.entries.append(ManifestEntry(sourceKey: key, filename: filename, size: entry.size, sha256: hash))
    }

    private func validateRoot(_ root: URL, identity: String) throws {
        var info = stat()
        guard lstat(root.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              try volumeIdentity(URL(fileURLWithPath: root.path, isDirectory: true)) == identity else { throw Failure.message("The original drive is disconnected or a different drive was selected.") }
        if let expected = activeRootSignature, expected.path == root.path {
            let actual = try rootSignature(root)
            guard info.st_dev == expected.device, (expected.isVolumeRoot || actual.inode == expected.inode), actual.isVolumeRoot == expected.isVolumeRoot else {
                throw Failure.message("Select the original drive root or original export location, not a copied folder.")
            }
        }
    }
    private func rootSignature(_ root: URL) throws -> (inode: UInt64, isVolumeRoot: Bool) {
        var info = stat()
        guard stat(root.path, &info) == 0 else { throw posixError("Could not identify the selected export location") }
        var freshRoot = URL(fileURLWithPath: root.path, isDirectory: true)
        freshRoot.removeAllCachedResourceValues()
        let volumeURL = try freshRoot.resourceValues(forKeys: [.volumeURLKey]).volume
        let volumeRoot = volumeURL?.resolvingSymlinksInPath().standardizedFileURL
        return (UInt64(info.st_ino), volumeRoot?.path == root.resolvingSymlinksInPath().standardizedFileURL.path)
    }
    private func validateFolder(_ folder: URL, root: URL, identity: String) throws {
        try validateRoot(root, identity: identity)
        guard folder.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path else { throw Failure.message("Export folder must remain inside the selected drive.") }
        var info = stat()
        guard lstat(folder.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { throw Failure.message("Export folder is missing or is a symbolic link.") }
        if let expected = activeFolderSignature, expected.path == folder.path,
           (UInt64(info.st_ino) != expected.inode || info.st_dev != expected.device) {
            throw Failure.message("The export folder was replaced while the operation was running.")
        }
    }
    private func acquireFolderLock(_ folder: URL) throws -> Int32 {
        let descriptor = open(folder.appendingPathComponent(".syncrosa-export.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw posixError("Could not lock the export folder") }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { close(descriptor); throw Failure.message("Another export is using this folder, or its lock is unsafe.") }
        return descriptor
    }
    private func openReader(_ url: URL) throws -> FileHandle {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError("Could not read \(url.lastPathComponent)") }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { close(descriptor); throw Failure.message("Only regular music files can be exported.") }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
    private func regularSize(_ url: URL) throws -> Int64 {
        guard !isSymlink(url) else { throw Failure.message("Symbolic-link export files are not reused.") }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize else { throw Failure.message("Not a regular music file.") }
        return Int64(size)
    }
    private func hashFile(_ url: URL, root: URL, identity: String, pollCancellation: Bool = true) throws -> (hash: String, size: Int64) {
        let reader = try openReader(url); defer { try? reader.close() }
        var before = stat(); guard fstat(reader.fileDescriptor, &before) == 0 else { throw posixError("Could not inspect source file") }
        var hasher = SHA256(); var size: Int64 = 0
        while let data = try reader.read(upToCount: 1024 * 1024), !data.isEmpty {
            if pollCancellation { try checkCancellation() }; try validateRoot(root, identity: identity)
            hasher.update(data: data); size += Int64(data.count)
        }
        var after = stat(); guard fstat(reader.fileDescriptor, &after) == 0, before.st_size == after.st_size, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec, size == Int64(after.st_size) else { throw Failure.message("A file changed while its contents were being checked. Try again.") }
        return (hex(hasher.finalize()), size)
    }
    private func cleanupTemporary(_ entry: inout Entry, in folder: URL, root: URL, identity: String) throws {
        try validateFolder(folder, root: root, identity: identity)
        guard let name = entry.temporaryName, let inode = entry.temporaryFileID else { return }
        let url = folder.appendingPathComponent(name)
        var info = stat()
        if lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, UInt64(info.st_ino) == inode {
            try FileManager.default.removeItem(at: url)
        }
        entry.temporaryName = nil; entry.temporaryFileID = nil
    }

    private func candidateNames(base: String, folder: URL, preferred: [String], safe: Bool) throws -> [String] {
        let url = URL(fileURLWithPath: base); let stem = url.deletingPathExtension().lastPathComponent; let ext = url.pathExtension
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        let candidates = files.filter { name in
            guard safeLeaf(name) else { return false }
            if name == base { return true }
            guard name.hasPrefix(stem + "_"), name.hasSuffix(ext.isEmpty ? "" : "." + ext) else { return false }
            let suffix = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent.dropFirst(stem.count + 1)
            return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
        }.sorted()
        // A changed naming policy must not claim an old incompatible name is safe.
        let compatible = preferred.filter { name in safeLeaf(name) && (!safe || name == base || candidates.contains(name)) }
        var seen = Set<String>()
        return (compatible + candidates).filter { seen.insert($0).inserted }
    }
    private func uniqueName(_ base: String, folder: URL, reserved: Set<String>) -> String {
        let url = URL(fileURLWithPath: base); let stem = url.deletingPathExtension().lastPathComponent; let ext = url.pathExtension
        var candidate = base; var suffix = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path) || isSymlink(folder.appendingPathComponent(candidate)) || reserved.contains(candidate.lowercased()) {
            candidate = stem + "_\(suffix)" + (ext.isEmpty ? "" : "." + ext); suffix += 1
        }
        return candidate
    }
    private func writePlaylistFiles(job: Job, manifest: inout Manifest, folder: URL, root: URL) throws {
        let entries = job.entries.filter { $0.selected && $0.completed }.compactMap(\.filename)
        guard !entries.isEmpty else { return }
        let body = Data(("#EXTM3U\n" + entries.joined(separator: "\n") + "\n").utf8)
        let digest = hex(SHA256.hash(data: body))
        for ext in [job.createM3U ? "m3u" : nil, job.createM3U8 ? "m3u8" : nil].compactMap({ $0 }) {
            try validateFolder(folder, root: root, identity: job.volumeID)
            let base = sanitizedFolderName(job.playlistName) + "." + ext
            var target: String?
            var alreadyWritten: String?
            let managed = (manifest.playlistFiles ?? [:]).keys.sorted().filter {
                $0 == base || ($0.hasPrefix(sanitizedFolderName(job.playlistName) + "_") && URL(fileURLWithPath: $0).pathExtension == ext)
            }
            var visited = Set<String>()
            for name in ([base] + managed).filter({ visited.insert($0).inserted }) {
                let candidate = folder.appendingPathComponent(name)
                guard let currentHash = try? hashFile(candidate, root: root, identity: job.volumeID, pollCancellation: false).hash else { continue }
                if currentHash == digest { alreadyWritten = name; break }
                if manifest.playlistFiles?[name] == currentHash { target = name; break }
            }
            if let alreadyWritten {
                manifest.playlistFiles = (manifest.playlistFiles ?? [:]).merging([alreadyWritten: digest]) { _, new in new }
                continue
            }
            let finalName = target ?? uniqueName(base, folder: folder, reserved: [])
            let targetURL = folder.appendingPathComponent(finalName)
            guard !isSymlink(targetURL) else { throw Failure.message("Playlist files cannot be symbolic links.") }
            try body.write(to: targetURL, options: .atomic)
            manifest.playlistFiles = (manifest.playlistFiles ?? [:]).merging([finalName: digest]) { _, new in new }
        }
    }

    private func filename(for track: TrackFile, safe: Bool) -> String {
        let artist = safe ? iPodSafeFilename(track.artist) : sanitizeFilename(track.artist)
        let title = safe ? iPodSafeFilename(track.name) : sanitizeFilename(track.name)
        let base = [artist, title].filter { !$0.isEmpty }.joined(separator: " - ")
        let ext = sanitizeFilename(URL(fileURLWithPath: track.filePath).pathExtension)
        return truncateUTF8(base.isEmpty ? "Track" : base, maxBytes: 180) + (ext.isEmpty ? "" : "." + String(ext.prefix(12)))
    }
    private func sourceKey(_ track: TrackFile) -> String {
        if let pid = track.persistentID?.uppercased(), pid.count == 16, pid.allSatisfy({ $0.isHexDigit }) { return "pid:" + pid }
        return "path:" + hex(SHA256.hash(data: Data(URL(fileURLWithPath: track.filePath).resolvingSymlinksInPath().standardizedFileURL.path.utf8)))
    }
    private func safeLeaf(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
    private func safeTemporary(_ name: String, job: UUID, entry: UUID) -> Bool { safeLeaf(name) && name.hasPrefix(".syncrosa-\(job.uuidString)-\(entry.uuidString)-") && name.hasSuffix(".part") }
    private func isSymlink(_ url: URL) -> Bool { var info = stat(); return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK }
    private func validHash(_ value: String) -> Bool { value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) } }
    private func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 { digest.map { String(format: "%02x", $0) }.joined() }
    private func posixError(_ context: String) -> Failure { .message("\(context): \(String(cString: strerror(errno)))") }
    private func sanitizeFilename(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:").union(.controlCharacters)).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func sanitizedFolderName(_ name: String) -> String {
        let result = sanitizeFilename(name).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return result.isEmpty ? "Syncrosa Playlist" : truncateUTF8(result, maxBytes: 180)
    }
    private func truncateUTF8(_ value: String, maxBytes: Int) -> String {
        var result = value
        while result.utf8.count > maxBytes { result.removeLast() }
        return result
    }
    private func iPodSafeFilename(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-"))
        let safe = String(folded.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" })
        let result = safe.replacingOccurrences(of: "_+", with: "_", options: .regularExpression).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: " ._-"))
        return result.isEmpty ? "Track" : String(result.prefix(80))
    }
    static func defaultVolumeIdentity(_ url: URL) throws -> String {
        var freshURL = URL(fileURLWithPath: url.path, isDirectory: true)
        freshURL.removeAllCachedResourceValues()
        if let uuid = try freshURL.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString { return "uuid:" + uuid }
        var info = stat()
        guard stat(url.path, &info) == 0 else { throw Failure.message("The selected drive is unavailable.") }
        return "device:\(info.st_dev)"
    }
    static func defaultAvailableCapacity(_ url: URL) throws -> Int64 {
        guard let capacity = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity else { throw Failure.message("Could not read free space on the selected drive.") }
        return Int64(capacity)
    }
}
