// Wavefront path state (REQ-GPU-005): the path core plus the queues and the structure-of-arrays
// state that carry paths between the select, extend and shade kernels. Mirrored in
// crates/verion-gpu-metal/src/wavefront.rs.
//
// params[30] is the bounce depth a dispatch works on, params[31] the path count N (one path per pixel).
// Path state word f of path p is at state[f * N + p]; WF_BASE words, then WF_SPLIT more when the
// lighting AOVs are on (params[28]).
//
// Adaptive sampling (params[32], REQ-ACC-007): before each sample, wf_select puts only the pixels
// that have not converged into the depth-0 queue (counts[0]); the other pixels take no more samples.

#include "pt_core.slang"

RWStructuredBuffer<uint> state;    // 19: path state, see above
RWStructuredBuffer<uint> hits;     // 20: 4 words per path: hit flag, instance, primitive, t (bits)
StructuredBuffer<uint> queueIn;    // 21: path ids live at this depth
RWStructuredBuffer<uint> queueOut; // 22: path ids that go on to the next depth
RWStructuredBuffer<uint> counts;   // 23: live paths per depth (counts[d] = length of the depth-d queue), then
                                   // the depth-0 count of the latest sample at counts[max depth + 1]
RWStructuredBuffer<uint> args;     // 24: indirect dispatch arguments, 3 words per depth

static const uint WF_GROUP = 64;
static const uint WF_BASE = 16;
static const uint WF_SPLIT = 17;

uint pathCount() { return params[31]; }

void putF(uint f, uint p, float v) { state[f * pathCount() + p] = asuint(v); }
float getF(uint f, uint p) { return asfloat(state[f * pathCount() + p]); }
void put3(uint f, uint p, float3 v) { putF(f, p, v.x); putF(f + 1, p, v.y); putF(f + 2, p, v.z); }
float3 get3(uint f, uint p) { return float3(getF(f, p), getF(f + 1, p), getF(f + 2, p)); }

// Words: 0 org, 3 dir, 6 throughput, 9 rng, 10 flags (cls in bits 0-1, chan + 1 in bits 2-3, misPrev
// in bit 4), 11 pathLen, 12 qPrev, 13 radiance total; with the lighting AOVs 16 the five parts, 31 visLit,
// 32 visTotal. Depth 0 keeps no state: its camera path is generated again from the pixel.
void storePath(PathState s, uint p)
{
    uint n = pathCount();
    put3(0, p, s.org);
    put3(3, p, s.dir);
    put3(6, p, s.thr);
    state[9 * n + p] = s.rng;
    state[10 * n + p] = s.cls | (uint(s.chan + 1) << 2) | (s.misPrev ? 16u : 0u);
    putF(11, p, s.pathLen);
    putF(12, p, s.qPrev);
    put3(13, p, s.parts.total);
    if (params[28] != 0)
    {
        put3(WF_BASE, p, s.parts.directDiffuse);
        put3(WF_BASE + 3, p, s.parts.indirectDiffuse);
        put3(WF_BASE + 6, p, s.parts.specular);
        put3(WF_BASE + 9, p, s.parts.transmission);
        put3(WF_BASE + 12, p, s.parts.emission);
        putF(WF_BASE + 15, p, s.visLit);
        putF(WF_BASE + 16, p, s.visTotal);
    }
}

PathState loadPath(uint p, uint depth)
{
    if (depth == 0)
        return generatePath(p % params[0], p / params[0]);
    uint n = pathCount();
    PathState s;
    s.org = get3(0, p);
    s.dir = get3(3, p);
    s.thr = get3(6, p);
    s.rng = state[9 * n + p];
    uint flags = state[10 * n + p];
    s.cls = flags & 3u;
    s.chan = int((flags >> 2) & 3u) - 1;
    s.misPrev = (flags & 16u) != 0;
    s.pathLen = getF(11, p);
    s.qPrev = getF(12, p);
    s.parts = (Parts)0;
    s.parts.total = get3(13, p);
    s.visLit = 0.0;
    s.visTotal = 0.0;
    if (params[28] != 0)
    {
        s.parts.directDiffuse = get3(WF_BASE, p);
        s.parts.indirectDiffuse = get3(WF_BASE + 3, p);
        s.parts.specular = get3(WF_BASE + 6, p);
        s.parts.transmission = get3(WF_BASE + 9, p);
        s.parts.emission = get3(WF_BASE + 12, p);
        s.visLit = getF(WF_BASE + 15, p);
        s.visTotal = getF(WF_BASE + 16, p);
    }
    return s;
}

// The path a thread of the depth's queue works on. Depth 0 takes every pixel in order with no queue,
// unless adaptive sampling chose the pixels (wf_select).
uint queuedPath(uint i, uint depth) { return depth == 0 && params[32] == 0 ? i : queueIn[i]; }
