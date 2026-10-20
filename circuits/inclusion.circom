pragma circom 2.0.8;

include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/multiplexer.circom";
include "circomlib/circuits/mux1.circom";
include "circomlib/circuits/switcher.circom";
include "circomlib/circuits/poseidon.circom";

/// Verifies that a node is included in a Skew Merkle Mountain Range (SkewMMR) 
/// with the given `roots`, `packedRanks` and `depth`.
/// 
/// Returns a validity flag and the index of the proven node within its tree.
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
    signal output index;

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

    // The proven node has rank `rank - pathLen`. Zeroed when the path does not fit, so a
    // non-member keeps a witness.
    component position = InsertionIndex(MAX_TREES);
    for (var i = 0; i < MAX_TREES; i++) {
        position.sizes[i] <== frontier.sizes[i];
    }
    position.tree <== tree;
    position.provenRank <== fits.out * (rank - pathLen);
    for (var i = 0; i < MAX_RANK; i++) {
        position.pathRight[i] <== pathRight[i];
        position.active[i] <== active[i];
    }
    index <== position.index;
}

/// Unpacks the 6-bit `rank`s and tree `sizes` from the `packedRanks` word of LibSkewMmr.sol.
template UnpackRanks(MAX_TREES) {
    var RANK_BITS = 6;
    assert(MAX_TREES <= 42);

    signal input packedRanks;
    signal output ranks[MAX_TREES];
    signal output sizes[MAX_TREES];

    component bits = Num2Bits(RANK_BITS * MAX_TREES);
    bits.in <== packedRanks;

    component rankBits[MAX_TREES];
    component span[MAX_TREES];
    for (var i = 0; i < MAX_TREES; i++) {
        rankBits[i] = Bits2Num(RANK_BITS);
        span[i] = Pow2(RANK_BITS);
        for (var b = 0; b < RANK_BITS; b++) {
            rankBits[i].in[b] <== bits.out[RANK_BITS * i + b];
            span[i].bits[b] <== bits.out[RANK_BITS * i + b];
        }
        ranks[i] <== rankBits[i].out;
        sizes[i] <== 2 * span[i].out - 1;
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

/// Returns the insertion index of the given node within the SkewMMR.
template InsertionIndex(MAX_TREES) {
    var MAX_RANK = MAX_TREES - 1;
    var RANK_BITS = 6;

    signal input sizes[MAX_TREES];
    signal input tree;
    signal input provenRank;
    signal input pathRight[MAX_RANK];
    signal input active[MAX_RANK];
    signal output index;

    component treeAt = Decoder(MAX_TREES);
    treeAt.inp <== tree;

    var through = 0;
    signal held[MAX_TREES];
    for (var i = MAX_TREES - 1; i >= 0; i--) {
        through += treeAt.out[i];
        held[i] <== through * sizes[i];
    }

    // The proven node's subtree holds `2^(rank + 1) - 1` elements.
    component provenBits = Num2Bits(RANK_BITS);
    provenBits.in <== provenRank;
    component provenSpan = Pow2(RANK_BITS);
    for (var b = 0; b < RANK_BITS; b++) {
        provenSpan.bits[b] <== provenBits.out[b];
    }

    // Each ancestor is one element ahead of its children, and its right child also follows
    // the left subtree, which holds `2^(provenRank + 1 + i) - 1` elements at step `i`.
    signal rightSpan[MAX_RANK];
    signal offset[MAX_RANK];
    for (var i = 0; i < MAX_RANK; i++) {
        rightSpan[i] <== pathRight[i] * 2 * provenSpan.out;
        offset[i] <== active[i] * (1 + rightSpan[i] * 2 ** i - pathRight[i]);
    }

    var elements = 0;
    for (var i = 0; i < MAX_TREES; i++) {
        elements += held[i];
    }
    var ahead = 0;
    for (var i = 0; i < MAX_RANK; i++) {
        ahead += offset[i];
    }
    index <== elements - 1 - ahead;
}

/// `2^n` for the `BITS`-bit `n` whose bits, low first, are `bits`. The bits must be binary.
template Pow2(BITS) {
    signal input bits[BITS];
    signal output out;

    signal acc[BITS + 1];
    acc[0] <== 1;
    for (var b = 0; b < BITS; b++) {
        acc[b + 1] <== acc[b] * (1 + bits[b] * (2 ** (2 ** b) - 1));
    }
    out <== acc[BITS];
}
