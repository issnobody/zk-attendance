include "circomlib/circuits/poseidon.circom";

template Proximity() {
    signal input nonce[2];          // 16 bytes → 2 field elements
    component h = Poseidon(2);
    h.inputs[0] <== nonce[0];
    h.inputs[1] <== nonce[1];
    signal output hash;
    hash <== h.out;
}
component main = Proximity();

