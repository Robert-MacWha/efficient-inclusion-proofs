pragma circom 2.2.0;

include "../../../circuits/inclusion.circom";

component main {public [roots, state, element]} = SkewMmrInclusion(26);
