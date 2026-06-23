import Foundation
import Cocoa
import Combine

struct USBDrive: Identifiable, Hashable {
    var id: String { volumeURL.path }
    let name: String
    let volumeURL: URL
    let totalSpace: Int64
    let freeSpace: Int64
    let filesystemType: String      // Raw system volume format name
    let filesystemLabel: String     // Human readable label
    
    var isAndroidCompatible: Bool {
        let typeLower = filesystemType.lowercased()
        let labelLower = filesystemLabel.lowercased()
        return typeLower.contains("msdos") || 
               typeLower.contains("fat") || 
               typeLower.contains("exfat") ||
               labelLower.contains("fat32") ||
               labelLower.contains("exfat")
    }
}

class USBService: ObservableObject {
    static let shared = USBService()
    
    @Published var availableDrives: [USBDrive] = []
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        startMonitoring()
        updateDrives()
    }
    
    func startMonitoring() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        
        NotificationCenter.default.publisher(for: NSWorkspace.didMountNotification, object: wsCenter)
            .sink { [weak self] _ in
                self?.updateDrives()
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSWorkspace.didUnmountNotification, object: wsCenter)
            .sink { [weak self] _ in
                self?.updateDrives()
            }
            .store(in: &cancellables)
    }
    
    func updateDrives() {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeLocalizedFormatDescriptionKey
        ]
        
        let fm = FileManager.default
        guard let urls = fm.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) else { return }
        
        var drives: [USBDrive] = []
        
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            
            let isRemovable = values.volumeIsRemovable ?? false
            let isEjectable = values.volumeIsEjectable ?? false
            
            // Only include external removable volumes mounted under /Volumes/
            if (isRemovable || isEjectable) && url.path.hasPrefix("/Volumes/") {
                let name = values.volumeName ?? url.lastPathComponent
                let totalSpace = Int64(values.volumeTotalCapacity ?? 0)
                let freeSpace = Int64(values.volumeAvailableCapacity ?? 0)
                let fsLabel = values.volumeLocalizedFormatDescription ?? "Unknown"
                
                // Retrieve raw filesystem type name using statfs
                let fsType = getRawFilesystemType(for: url)
                
                let drive = USBDrive(
                    name: name,
                    volumeURL: url,
                    totalSpace: totalSpace,
                    freeSpace: freeSpace,
                    filesystemType: fsType,
                    filesystemLabel: fsLabel
                )
                
                // Prevent duplicate mount points (e.g. nested or system mounts)
                if !drives.contains(where: { $0.volumeURL == drive.volumeURL }) {
                    drives.append(drive)
                }
            }
        }
        
        DispatchQueue.main.async {
            self.availableDrives = drives
        }
    }
    
    private func getRawFilesystemType(for url: URL) -> String {
        var stats = statfs()
        let path = url.path
        if statfs(path, &stats) == 0 {
            let typeName = withUnsafeBytes(of: stats.f_fstypename) { rawBuffer -> String in
                if let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: CChar.self) {
                    return String(cString: ptr)
                }
                return "unknown"
            }
            return typeName
        }
        return "unknown"
    }
}
