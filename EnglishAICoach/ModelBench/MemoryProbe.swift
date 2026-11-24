import Darwin
import Foundation
import os

/// Mesures de mémoire de l'app (lecture seule).
enum MemoryProbe {
    /// Mémoire que le système laisse encore à l'app avant de la terminer.
    static func availableBytes() -> Int64 {
        Int64(os_proc_available_memory())
    }

    /// Empreinte mémoire de l'app (celle que le système surveille).
    static func footprintBytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), raw, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : -1
    }

    static func text(_ bytes: Int64) -> String {
        bytes < 0 ? "n/d" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}

/// Relève régulièrement la mémoire pendant un essai, pour en garder le pire moment.
@MainActor
final class MemorySampler {
    private(set) var minAvailable: Int64 = Int64.max
    private(set) var maxFootprint: Int64 = 0
    private var task: Task<Void, Never>?

    func start() {
        minAvailable = Int64.max
        maxFootprint = 0
        sample()
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        sample()
    }

    private func sample() {
        minAvailable = min(minAvailable, MemoryProbe.availableBytes())
        maxFootprint = max(maxFootprint, MemoryProbe.footprintBytes())
    }
}
