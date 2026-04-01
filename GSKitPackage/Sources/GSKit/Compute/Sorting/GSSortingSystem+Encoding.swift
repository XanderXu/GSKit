import Foundation
import RealityKit
import simd

@available(macOS 26.0, *)
@available(visionOS 2.0, *)

extension GSSortingSystem {

    // MARK: - Sort Result

    struct GSCpuSortResult: @unchecked Sendable {
        let indices: [UInt32]
        let entityID: ObjectIdentifier
    }

    // MARK: - Thread-safe Result Transfer

    nonisolated(unsafe) static var pendingSortResult: GSCpuSortResult?
    nonisolated(unsafe) static var pendingSortLock: NSLock = NSLock()

    nonisolated static func submitSortResult(_ result: GSCpuSortResult) {
        pendingSortLock.lock()
        pendingSortResult = result
        pendingSortLock.unlock()
    }

    nonisolated static func consumePendingSortResult(for entityID: ObjectIdentifier) -> GSCpuSortResult? {
        pendingSortLock.lock()
        defer { pendingSortLock.unlock() }
        guard let result = pendingSortResult, result.entityID == entityID else {
            return nil
        }
        pendingSortResult = nil
        return result
    }

    // MARK: - CPU Radix Sort

    /// 3-pass LSD radix sort using 11 bits per pass (covers full UInt32 range).
    /// Sorts splats by depth (back-to-front) and returns the sorted splat indices.
    nonisolated static func performCpuSort(
        positions: [SIMD3<Float>],
        cameraPos: SIMD3<Float>,
        cameraForward: SIMD3<Float>,
        count: Int,
        entityID: ObjectIdentifier
    ) -> GSCpuSortResult {
        typealias Entry = (key: UInt32, index: UInt32)

        let capacity = count
        var source = [Entry](repeating: (0, 0), count: capacity)
        var dest = [Entry](repeating: (0, 0), count: capacity)

        // 1. Compute depth keys
        for i in 0..<count {
            let depth = simd_dot(positions[i] - cameraPos, cameraForward)
            // Negate depth so that farther splats (larger depth) sort first (smaller key)
            let key = UInt32(clamping: Int64((-depth + 10_000.0) * 1_000.0))
            source[i] = (key, UInt32(i))
        }

        // 2. LSD radix sort: 3 passes x 11 bits (covers 33 bits > 32-bit key)
        let bitsPerPass = 11
        let radixSize = 1 << bitsPerPass  // 2048
        let mask = UInt32(radixSize - 1)

        for pass in 0..<3 {
            let shift = UInt32(pass * bitsPerPass)

            // Count
            var counts = [Int](repeating: 0, count: radixSize)
            for i in 0..<count {
                let digit = Int((source[i].key >> shift) & mask)
                counts[digit] += 1
            }

            // Prefix sum
            var total = 0
            for d in 0..<radixSize {
                let c = counts[d]
                counts[d] = total
                total += c
            }

            // Scatter
            for i in 0..<count {
                let digit = Int((source[i].key >> shift) & mask)
                dest[counts[digit]] = source[i]
                counts[digit] += 1
            }

            swap(&source, &dest)
        }

        // 3. Extract sorted indices (source now has final sorted order)
        var sortedIndices = [UInt32](repeating: 0, count: count)
        for i in 0..<count {
            sortedIndices[i] = source[i].index
        }

        return GSCpuSortResult(indices: sortedIndices, entityID: entityID)
    }

    /// Expand sorted splat indices into quad index buffer and write to LowLevelMesh.
    static func writeSortedIndices(
        _ sortedIndices: [UInt32],
        activeCount: Int,
        to lowLevelMesh: LowLevelMesh
    ) {
        let count = min(activeCount, sortedIndices.count)
        guard count > 0 else { return }

        lowLevelMesh.replaceUnsafeMutableIndices { destination in
            guard let destPtr = destination.baseAddress?.assumingMemoryBound(to: UInt32.self) else { return }
            for i in 0..<count {
                let splatIdx = sortedIndices[i]
                let base = splatIdx &* 4  // 4 vertices per quad
                let offset = i &* 6       // 6 indices per quad
                destPtr[offset + 0] = base + 0
                destPtr[offset + 1] = base + 1
                destPtr[offset + 2] = base + 2
                destPtr[offset + 3] = base + 0
                destPtr[offset + 4] = base + 2
                destPtr[offset + 5] = base + 3
            }
        }
    }
}
