pragma solidity ^0.4.15;

import "./common-onchain.sol";

contract Judge is CommonOnchain {

    address winner;

    function judge(bytes32[13] res, uint q,
                        bytes32[] _proof,
                        bytes32 vm_, bytes32 op, uint[4] regs,
                        bytes32[10] roots, uint[4] pointers) public returns (uint) {
        setMachine(vm_, op, regs[0], regs[1], regs[2], regs[3]);
        setVM2(roots, pointers);
        // Special initial state
        if (q == 0) {
            m.vm = hashVM();
            state = hashMachine();
            require(m.vm == res[q]);
        }
        else {
           state = res[q];
           require(state == hashMachine());
        }
        phase = q;
        proof = _proof;
        performPhase();
        // Special final state
        if (q == 11) state = m.vm;
        require (state == res[q+1]);
        winner = msg.sender;
        return q;
        // return (q, state, debug);
    }

    function judgeFinality(bytes32[13] res, bytes32[] _proof,
                        bytes32[10] roots, uint[4] pointers) public returns (uint) {
        setVM2(roots, pointers);
        m.vm = hashVM();
        state = hashMachine();
        require(m.vm == res[0]);
        phase = 0;
        proof = _proof;
        performPhase();
        require(m.op == 0x0000000000000000000000000000000000000000040006060001000106000000);
        return 1;
    }

    function checkFileProof(bytes32 state, bytes32[10] roots, uint[4] pointers, bytes32[] _proof, uint loc) public returns (bool) {
        setVM2(roots, pointers);
        proof = _proof;
        return state == calcIOHash(roots) && vm_r.input_data == getRoot(loc);
    }

    function checkProof(bytes32 hash, bytes32 root, bytes32[] _proof, uint loc) public returns (bool) {
        proof = _proof;
        return uint(hash) == getLeaf(loc) && root == getRoot(loc);
    }

    function calcStateHash(bytes32[10] roots, uint[4] pointers) public returns (bytes32) {
        setVM2(roots, pointers);
        return hashVM();
    }

    function calcIOHash(bytes32[10] roots) public pure returns (bytes32) {
        return keccak256(roots[0], roots[7], roots[8], roots[9]);
    }

}
