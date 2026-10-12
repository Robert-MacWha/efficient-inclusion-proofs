pragma circom 2.0.8;

include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/multiplexer.circom";
include "circomlib/circuits/mux1.circom";
include "circomlib/circuits/switcher.circom";
include "circomlib/circuits/poseidon.circom";

/// Outputs a `valid` boolean when `element` is held by the accumulator described by `roots`,
/// `packedRanks` and `depth`.
///
/// They must come from the same frontier and be authenticated by the caller. Signals that are
/// not well formed (ranks or a depth wider than their packing, a direction that is not a bit,
/// a `tree` past `MAX_TREES`) have no witness at all.
template SkewMmrInclusion(MAX_TREES) {
    // A frontier at capacity holds ranks `MAX_TREES - 1 .. 0`, so no tree within capacity
    // outgrows this and no path is longer than it.
    var MAX_RANK = MAX_TREES - 1;
    // `rank`s are packed into `packedRanks` at this width, and `depth` is held to it.
    var RANK_BITS = 6;

    signal input roots[MAX_TREES];
    signal input packedRanks;
    signal input depth;
    signal input element;
    signal input tree;
    signal input children[2];
    signal input pathLen;
    signal input pathElements[MAX_RANK];
    signal input pathSiblings[MAX_RANK];
    signal input pathRight[MAX_RANK];
    signal output valid;

    component frontier = UnpackRanks(MAX_TREES);
    frontier.packedRanks <== packedRanks;

    component depthBits = Num2Bits(RANK_BITS);
    depthBits.in <== depth;

    // Select the root and rank of the tree that the proven node belongs to.
    component selected = Multiplexer(2, MAX_TREES);
    selected.sel <== tree;
    for (var i = 0; i < MAX_TREES; i++) {
        selected.inp[i][0] <== roots[i];
        selected.inp[i][1] <== frontier.ranks[i];
    }
    signal root <== selected.out[0];
    signal rank <== selected.out[1];

    // Stops the proof selecting a root above the frontier.
    component live = LessThan(RANK_BITS);
    live.in[0] <== tree;
    live.in[1] <== depth;

    component fits = LessEqThan(RANK_BITS);
    fits.in[0] <== pathLen;
    fits.in[1] <== rank;

    // One-hot `path.len()`, so the per-step flags below are a monotone prefix. A proof is only
    // valid with `pathLen` in `0..MAX_RANK`.
    component length = Decoder(MAX_RANK + 1);
    length.inp <== pathLen;

    var active[MAX_RANK];
    var suffix = 0;
    for (var i = MAX_RANK - 1; i >= 0; i--) {
        suffix += length.out[i + 1];
        active[i] = suffix;
    }

    // One step per level between the proven node and the tree root, so a node reached by
    // `L` steps in a tree of rank `r` has rank `r - L`, and is a leaf exactly when `L == r`.
    component isLeaf = IsEqual();
    isLeaf.in[0] <== pathLen;
    isLeaf.in[1] <== rank;

    component node = Poseidon(3);
    node.inputs[0] <== element;
    node.inputs[1] <== children[0];
    node.inputs[2] <== children[1];

    component proven = Mux1();
    proven.c[0] <== node.out;
    proven.c[1] <== element;
    proven.s <== isLeaf.out;

    signal current[MAX_RANK + 1];
    current[0] <== proven.out;

    component step[MAX_RANK];
    for (var i = 0; i < MAX_RANK; i++) {
        step[i] = FoldStep();
        step[i].current <== current[i];
        step[i].element <== pathElements[i];
        step[i].sibling <== pathSiblings[i];
        step[i].right <== pathRight[i];
        step[i].active <== active[i];
        current[i + 1] <== step[i].out;
    }

    component folds = IsEqual();
    folds.in[0] <== current[MAX_RANK];
    folds.in[1] <== root;

    signal placed <== live.out * fits.out;
    signal bounded <== placed * length.success;
    valid <== bounded * folds.out;
}

/// Unpacks the 6-bit `rank`s from the `packedRanks` word of LibSkewMmr.sol.
template UnpackRanks(MAX_TREES) {
    var RANK_BITS = 6;
    assert(MAX_TREES <= 42);

    signal input packedRanks;
    signal output ranks[MAX_TREES];

    component bits = Num2Bits(RANK_BITS * MAX_TREES);
    bits.in <== packedRanks;

    component rankBits[MAX_TREES];
    for (var i = 0; i < MAX_TREES; i++) {
        rankBits[i] = Bits2Num(RANK_BITS);
        for (var b = 0; b < RANK_BITS; b++) {
            rankBits[i].in[b] <== bits.out[RANK_BITS * i + b];
        }
        ranks[i] <== rankBits[i].out;
    }
}

/// One ancestor of the proven node. Steps past `path.len()` pass `current` through unchanged.
template FoldStep() {
    signal input current;
    signal input element;
    signal input sibling;
    /// Whether the path descends into the right child.
    signal input right;
    signal input active;
    signal output out;

    // `Switcher` assumes a binary selector without constraining it.
    right * (right - 1) === 0;

    component order = Switcher();
    order.sel <== right;
    order.L <== current;
    order.R <== sibling;

    component hash = Poseidon(3);
    hash.inputs[0] <== element;
    hash.inputs[1] <== order.outL;
    hash.inputs[2] <== order.outR;

    component gate = Mux1();
    gate.c[0] <== current;
    gate.c[1] <== hash.out;
    gate.s <== active;

    out <== gate.out;
}
