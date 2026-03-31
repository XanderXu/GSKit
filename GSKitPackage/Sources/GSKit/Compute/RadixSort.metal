//
//  RadixSort.metal
//  GSKit
//

#include <metal_stdlib>
using namespace metal;

struct GSInstanceData {
    float3 position;
};

struct GSDepthEntry {
    uint index;
    float depth;
};

struct GSDepthParams {
    float4 cameraLocalPos;
    float4 cameraLocalForward;
    uint count;
    uint paddedCount;
    uint2 padding;
};

struct GSRadixPassParams {
    uint paddedCount;
    uint shift;
    uint numGroups;
    uint padding;
};

struct GSRadixScanParams {
    uint numGroups;
    uint padding0;
    uint padding1;
    uint padding2;
};

struct GSWriteIndicesParams {
    uint activeCount;
    uint padding0;
    uint padding1;
    uint padding2;
};

#define GS_DEPTH_KEY_MASK 0x00FFFFFFu
#define GS_DEPTH_KEY_MAX_FLOAT 16777215.0f
#define GS_DEPTH_KEY_BIAS 10000.0f
#define GS_DEPTH_KEY_SCALE (GS_DEPTH_KEY_MAX_FLOAT / (2.0f * GS_DEPTH_KEY_BIAS))

inline uint gskit_pack_depth_key24(float depth)
{
    float scaled = (depth + GS_DEPTH_KEY_BIAS) * GS_DEPTH_KEY_SCALE;
    return (uint)clamp(scaled, 0.0f, GS_DEPTH_KEY_MAX_FLOAT);
}

inline uint gskit_radix_digit(uint key, uint shift)
{
    uint invertedKey = (~key) & GS_DEPTH_KEY_MASK;
    return (invertedKey >> shift) & 0xFFu;
}

// --- Pass 1: Compute Depths ---
// Calculate planar depth (dot product against camera forward vector) encoding an ordered key.
kernel void gskit_calculate_depths(
    device const GSInstanceData *instances [[buffer(0)]],
    device const uint *visibleIndices [[buffer(1)]],
    device uint2 *outEntries [[buffer(2)]], // x = key (depth), y = payload (index)
    constant GSDepthParams &params [[buffer(3)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= params.paddedCount) return;

    if (tid >= params.count) {
        // Pad with the minimum key so padded entries remain at the end of descending depth order.
        outEntries[tid] = uint2(0u, 0u);
        return;
    }

    uint splatIndex = visibleIndices[tid];
    float3 p = instances[splatIndex].position;

    // Furthest splats should render first. We keep depth monotonic in a 24-bit key
    // and invert during radix digit extraction to preserve descending depth order.
    float depth = dot(p - params.cameraLocalPos.xyz, params.cameraLocalForward.xyz);
    uint key = gskit_pack_depth_key24(depth);

    outEntries[tid] = uint2(key, splatIndex);
}

// --- Radix Sort Support ---
// A multi-pass Radix Sort utilizing tree-reduction for histogram scanning.
// This executes 2-3 passes (8 bits per pass) over a 24-bit depth key target. Apple Silicon
// requires a strict Multi-Pass approach (like FidelityFX) rather than a Single-Pass
// atomic Onesweep due to a lack of forward-progress guarantees.

#define RADIX_THREADS_PER_GROUP 256
#define RADIX_DIGITS 256
#define RADIX_MAX_SIMD_GROUPS 8

kernel void gskit_radix_count(
    device const uint2 *entries [[buffer(0)]],
    device uint *groupHistograms [[buffer(1)]],
    constant GSRadixPassParams &params [[buffer(2)]],
    uint tid [[thread_position_in_grid]],
    uint lid [[thread_position_in_threadgroup]],
    uint groupId [[threadgroup_position_in_grid]])
{
    threadgroup atomic_uint localHist[RADIX_DIGITS];

    // Initialize shared memory
    if (lid < RADIX_DIGITS) {
        atomic_store_explicit(&localHist[lid], 0u, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (tid < params.paddedCount) {
        uint key = entries[tid].x;
        uint digit = gskit_radix_digit(key, params.shift);
        atomic_fetch_add_explicit(&localHist[digit], 1u, memory_order_relaxed);
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Write local histogram out to global memory matrix [threadgroup][digit] for perfect coalescing
    if (lid < RADIX_DIGITS) {
        groupHistograms[groupId * RADIX_DIGITS + lid] = atomic_load_explicit(&localHist[lid], memory_order_relaxed);
    }
}

// Global prefix sum of the digit counts.
kernel void gskit_radix_scan(
    device uint *groupHistograms [[buffer(0)]],
    constant GSRadixScanParams &params [[buffer(1)]],
    uint lid [[thread_position_in_threadgroup]])
{
    // Single-threadgroup scan over [group][digit] counts.
    // Output layout:
    // - row 0: per-digit global base offsets
    // - row g>0: per-digit exclusive group prefixes (without global base added)
    threadgroup uint localDigitTotal[RADIX_DIGITS];

    uint d = lid; // Each thread handles exactly one digit
    if (d < RADIX_DIGITS) {
        uint myTotalCount = 0;
        for (uint g = 0; g < params.numGroups; ++g) {
            uint count = groupHistograms[g * RADIX_DIGITS + d];
            groupHistograms[g * RADIX_DIGITS + d] = myTotalCount;
            myTotalCount += count;
        }
        localDigitTotal[d] = myTotalCount;
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    // A single thread computes the absolute starting base offsets for each digit globally
    if (lid == 0) {
        uint runningSum = 0;
        for (uint i = 0; i < RADIX_DIGITS; ++i) {
            uint count = localDigitTotal[i];
            localDigitTotal[i] = runningSum;
            runningSum += count;
        }
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Write per-digit global bases to row 0.
    if (d < RADIX_DIGITS) {
        groupHistograms[d] = localDigitTotal[d];
    }
}

kernel void gskit_radix_scatter(
    device const uint2 *inEntries [[buffer(0)]],
    device uint2 *outEntries [[buffer(1)]],
    device const uint *groupHistograms [[buffer(2)]],
    constant GSRadixPassParams &params [[buffer(3)]],
    uint tid [[thread_position_in_grid]],
    uint lid [[thread_position_in_threadgroup]],
    uint groupId [[threadgroup_position_in_grid]],
    uint laneId [[thread_index_in_simdgroup]],
    uint simdGroupId [[simdgroup_index_in_threadgroup]],
    uint simdSize [[threads_per_simdgroup]])
{
    threadgroup ushort simdPrefix[RADIX_MAX_SIMD_GROUPS][RADIX_DIGITS];
    threadgroup uint digitBaseOffsets[RADIX_DIGITS];
    threadgroup uint groupDigitOffsets[RADIX_DIGITS];
    threadgroup uint localDigits[RADIX_THREADS_PER_GROUP];

    uint simdGroupCount = (RADIX_THREADS_PER_GROUP + simdSize - 1) / simdSize;
    bool simdPathAvailable = simdGroupCount <= RADIX_MAX_SIMD_GROUPS;
    bool isActive = tid < params.paddedCount;

    uint2 myEntry = uint2(0u, 0u);
    uint myDigit = RADIX_DIGITS;
    if (isActive) {
        myEntry = inEntries[tid];
        myDigit = gskit_radix_digit(myEntry.x, params.shift);
    }
    localDigits[lid] = myDigit;

    if (lid < RADIX_DIGITS) {
        digitBaseOffsets[lid] = groupHistograms[lid];
        groupDigitOffsets[lid] = (groupId == 0) ? 0u : groupHistograms[groupId * RADIX_DIGITS + lid];
        if (simdPathAvailable) {
            for (uint g = 0; g < simdGroupCount; ++g) {
                simdPrefix[g][lid] = 0;
            }
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    uint mySimdOffset = 0;
    uint mySimdTotal = 0;

    if (simdPathAvailable && isActive) {
        for (uint i = 0; i < simdSize; ++i) {
            uint otherDigit = simd_broadcast(myDigit, i);
            if (otherDigit == myDigit) {
                if (i < laneId) {
                    mySimdOffset++;
                }
                mySimdTotal++;
            }
        }

        if (mySimdOffset == 0) {
            simdPrefix[simdGroupId][myDigit] = (ushort)mySimdTotal;
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (isActive) {
        uint crossSimdOffset = 0;
        if (simdPathAvailable) {
            for (uint g = 0; g < simdGroupId; ++g) {
                crossSimdOffset += (uint)simdPrefix[g][myDigit];
            }
        } else {
            for (uint i = 0; i < lid; ++i) {
                if (localDigits[i] == myDigit) {
                    crossSimdOffset++;
                }
            }
        }

        uint globalDestIndex = digitBaseOffsets[myDigit] + groupDigitOffsets[myDigit] + crossSimdOffset + mySimdOffset;
        outEntries[globalDestIndex] = myEntry;
    }
}

// --- Final Pass: Matrix Write ---
kernel void gskit_write_indices(
    device const uint2 *sortedEntries [[buffer(0)]], // x = key, y = original splat index
    device uint *outIndices [[buffer(1)]],
    constant GSWriteIndicesParams &params [[buffer(2)]],
    uint tid [[thread_position_in_grid]])
{
    if (tid >= params.activeCount) return;

    uint writePos = tid * 6;
    uint splatIndex = sortedEntries[tid].y;
    uint v0 = splatIndex * 4;
    outIndices[writePos + 0] = v0 + 0;
    outIndices[writePos + 1] = v0 + 1;
    outIndices[writePos + 2] = v0 + 2;
    outIndices[writePos + 3] = v0 + 0;
    outIndices[writePos + 4] = v0 + 2;
    outIndices[writePos + 5] = v0 + 3;
}
