pragma circom 2.2.0;

include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/multiplexer.circom";
include "circomlib/circuits/mux1.circom";
include "circomlib/circuits/switcher.circom";
include "circomlib/circuits/poseidon.circom";

/// Verifies that `element` is held by the accumulator described by `roots` and `state`.
///
/// `roots` and `state` must come from the same frontier and be authenticated by the
/// caller.
template SkewMmrInclusion(MAX_TREES) {
    // A frontier at capacity holds ranks `MAX_TREES - 1 .. 0`, so no tree within capacity
    // outgrows this and no path is longer than it.
    var MAX_RANK = MAX_TREES - 1;
    // `rank` and `depth` are bytes of `state`, so comparisons against them are byte-wide.
    var BYTE_BITS = 8;

    signal input roots[MAX_TREES];
    signal input state;
    signal input element;
    signal input tree;
    signal input children[2];
    signal input pathLen;
    signal input pathElements[MAX_RANK];
    signal input pathSiblings[MAX_RANK];
    signal input pathRight[MAX_RANK];

    component frontier = UnpackState(MAX_TREES);
    frontier.state <== state;

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
    component live = LessThan(BYTE_BITS);
    live.in[0] <== tree;
    live.in[1] <== frontier.depth;
    live.out === 1;

    component fits = LessEqThan(BYTE_BITS);
    fits.in[0] <== pathLen;
    fits.in[1] <== rank;
    fits.out === 1;

    // One-hot `path.len()`, so the per-step flags below are a monotone prefix and `pathLen`
    // is bound to `0..MAX_RANK`.
    component length = Decoder(MAX_RANK + 1);
    length.inp <== pathLen;
    length.success === 1;

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

    current[MAX_RANK] === root;
}

/// Unpacks the frontier from the `state` word of SkewMmr.sol: 
///  - 0..25   - `rank`s
///  - 26      - `depth`
///  - 27..30  - `count`
///  - 31      - sentinel
template UnpackState(MAX_TREES) {
    var DEPTH_BYTE = 26;
    var SENTINEL_BIT = 248;
    assert(MAX_TREES <= DEPTH_BYTE);

    signal input state;
    signal output ranks[MAX_TREES];
    signal output depth;

    component bits = Num2Bits(SENTINEL_BIT + 1);
    bits.in <== state;

    component rankBytes[MAX_TREES];
    for (var i = 0; i < MAX_TREES; i++) {
        rankBytes[i] = Bits2Num(8);
        for (var b = 0; b < 8; b++) {
            rankBytes[i].in[b] <== bits.out[8 * i + b];
        }
        ranks[i] <== rankBytes[i].out;
    }

    component depthByte = Bits2Num(8);
    for (var b = 0; b < 8; b++) {
        depthByte.in[b] <== bits.out[8 * DEPTH_BYTE + b];
    }
    depth <== depthByte.out;
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
