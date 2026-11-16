pragma circom 2.0.8;

include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/multiplexer.circom";
include "circomlib/circuits/mux1.circom";
include "circomlib/circuits/switcher.circom";
include "circomlib/circuits/poseidon.circom";

/// Verifies the MMR inclusion proof of `element` against the tree `roots`, reporting whether
/// it holds in `valid`.
///
/// `roots` must be bound to authenticated public inputs, with entries above the frontier's
/// depth set to 0. A direction that is not a bit has no witness at all.
template SkewMmrInclusion(MAX_DEPTH) {
    signal input roots[MAX_DEPTH];
    signal input element;
    /// Index into `roots`.
    signal input tree;
    /// The children of the proven node. Ignored when it is a leaf.
    signal input children[2];
    /// Populated steps of `path`.
    signal input pathLen;
    /// Ancestors of the proven node, closest first. Steps from `pathLen` on are padding.
    signal input pathElements[MAX_DEPTH];
    signal input pathSiblings[MAX_DEPTH];
    signal input pathRight[MAX_DEPTH];
    signal output valid;

    // Zero when `tree` falls outside `0..MAX_DEPTH`.
    component treeAt = Decoder(MAX_DEPTH);
    treeAt.inp <== tree;
    component selected = EscalarProduct(MAX_DEPTH);
    for (var i = 0; i < MAX_DEPTH; i++) {
        selected.in1[i] <== treeAt.out[i];
        selected.in2[i] <== roots[i];
    }

    // One-hot `pathLen`, so the per-step flags `i < pathLen` below are a monotone prefix.
    // `success` holds whether it lands in `0..=MAX_DEPTH`.
    component length = Decoder(MAX_DEPTH + 1);
    length.inp <== pathLen;

    var active[MAX_DEPTH];
    var suffix = 0;
    for (var i = MAX_DEPTH - 1; i >= 0; i--) {
        suffix += length.out[i + 1];
        active[i] = suffix;
    }

    // Every node, leaf or not, hashes its element with its children.
    component node = Poseidon(3);
    node.inputs[0] <== element;
    node.inputs[1] <== children[0];
    node.inputs[2] <== children[1];

    signal current[MAX_DEPTH + 1];
    current[0] <== node.out;

    component step[MAX_DEPTH];
    for (var i = 0; i < MAX_DEPTH; i++) {
        step[i] = FoldStep();
        step[i].current <== current[i];
        step[i].element <== pathElements[i];
        step[i].sibling <== pathSiblings[i];
        step[i].right <== pathRight[i];
        step[i].active <== active[i];
        current[i + 1] <== step[i].out;
    }

    component folds = IsEqual();
    folds.in[0] <== current[MAX_DEPTH];
    folds.in[1] <== selected.out;

    valid <== length.success * folds.out;
}

/// One ancestor of the proven node. Steps past `pathLen` pass `current` through unchanged.
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
