pragma circom 2.2.0;

include "circomlib/circuits/poseidon.circom";

template Hash3() {
    signal input element;
    signal input left;
    signal input right;
    signal output out;

    component hash = Poseidon(3);
    hash.inputs[0] <== element;
    hash.inputs[1] <== left;
    hash.inputs[2] <== right;

    out <== hash.out;
}
