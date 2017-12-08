pragma solidity ^0.4.16;

interface JudgeInterface {
    function judge(bytes32[13] res, uint q,
                        bytes32[] _proof,
                        bytes32 vm_, bytes32 op, uint[4] regs,
                        bytes32[10] roots, uint[4] pointers) public returns (uint);
    function judgeFinality(bytes32[13] res, bytes32[] _proof,
                        bytes32[10] roots, uint[4] pointers) public returns (uint);
    function checkFileProof(bytes32 state, bytes32[10] roots, uint[4] pointers, bytes32[] proof, uint loc) public returns (bool);
    function checkProof(bytes32 hash, bytes32 root, bytes32[] proof, uint loc) public returns (bool);

    function calcStateHash(bytes32[10] roots, uint[4] pointers) public returns (bytes32);
    function calcIOHash(bytes32[10] roots) public returns (bytes32);
}

contract Interactive2 {

    JudgeInterface judge;

    mapping (uint => uint) blocked;
    mapping (uint => bool) rejected;
    
    enum State {
        Started,
        Running, // First and last state have been set up ... but this will mean that the verification game is running now
        Finished, // Winner has been chosen
        NeedErrorPhases,
        NeedPhases,
        PostedErrorPhases,
        PostedPhases,
        SelectedErrorPhase,
        SelectedPhase,
        
        /* Special states for finality */
        Finality
    }

    struct Record {
        uint256 task_id;
    
        address prover;
        address challenger;
        
        bytes32 start_state; // actually initial code + input
        bytes32 end_state; // actually output
        
        // Maybe number of steps should be finished
        uint256 steps;
        
        address winner;
        address next;
        
        uint256 size;
        uint256 timeout;
        uint256 clock;
        
        uint256 idx1;
        uint256 idx2;
        
        uint256 phase;
        
        bytes32[] proof;
        bytes32[13] result;
        
        State state;
        
        bytes32 sub_task;
    }

    function Interactive2(address addr) public {
        judge = JudgeInterface(addr);
    }

    mapping (bytes32 => Record) records;
    // mapping (bytes32 => VMParameters) params;

    event StartChallenge(address p, address c, bytes32 s, bytes32 e, uint256 par, uint to, bytes32 uniq);

    function make(uint task_id, address p, address c, bytes32 s, bytes32 e, uint256 par, uint to) public returns (bytes32) {
        bytes32 uniq = keccak256(task_id, p, c, s, e, par, to);
        Record storage r = records[uniq];
        r.task_id = task_id;
        r.prover = p;
        r.challenger = c;
        r.start_state = s;
        r.end_state = e;
        r.timeout = to;
        r.clock = block.number;
        r.next = r.prover;
        r.idx1 = 0;
        r.phase = 16;
        r.size = par;
        r.state = State.Started;
        /*
        r.steps = _steps;
        if (r.size > r.steps - 2) r.size = r.steps-2;
        r.proof.length = r.steps;
        r.proof[0] = s;
        r.proof[r.steps-1] = e;
        r.idx2 = r.steps-1;
        */
        r.state = State.Started;
        StartChallenge(p, c, s, e, r.size, to, uniq);
        blocked[task_id] = r.clock + r.timeout;
        return uniq;
    }
    
    function initialize(bytes32 id, bytes32[10] s_roots, uint[4] s_pointers, uint _steps,
                                    bytes32[10] e_roots, uint[4] e_pointers) public {
        Record storage r = records[id];
        require(msg.sender == r.next && r.state == State.Started);
        // check first state here
        require (r.start_state == judge.calcIOHash(s_roots));
        // then last one
        require (r.end_state == judge.calcIOHash(e_roots));
        
        // Now we can initialize
        r.steps = _steps;
        if (r.size > r.steps - 2) r.size = r.steps-2;
        r.idx2 = r.steps-1;
        r.proof.length = r.steps;
        r.proof[0] = judge.calcStateHash(s_roots, s_pointers);
        r.proof[r.steps-1] = judge.calcStateHash(e_roots, e_pointers);
        r.state = State.Running;
    }
    
    function getDescription(bytes32 id) public view returns (bytes32 init, uint steps, bytes32 last) {
        Record storage r = records[id];
        return (r.proof[0], r.steps, r.proof[r.steps-1]);
    }
    
    function getChallenger(bytes32 id) public view returns (address) {
       return records[id].challenger;
    }
    
    function getIndices(bytes32 id) public view returns (uint idx1, uint idx2) {
        Record storage r = records[id];
        return (r.idx1, r.idx2);
    }

    event StartFinalityChallenge(address p, address c, bytes32 s, bytes32 e, uint256 step, uint to, bytes32 uniq);

    // Solver thinks this is a final state, verifier disagrees
    // Solver has to post a proof that the next instruction is the "EXIT" opcode
    function makeFinality(uint task_id, address p, address c, bytes32 s, bytes32 e, uint256 _steps, uint to) public returns (bytes32) {
        bytes32 uniq = keccak256(task_id, p, c, s, e, _steps, to);
        Record storage r = records[uniq];
        r.task_id = task_id;
        r.prover = p;
        r.challenger = c;
        r.start_state = s;
        r.end_state = e;
        r.steps = _steps;
        r.timeout = to;
        r.clock = block.number;
        r.next = r.prover;
        r.phase = 20;
        r.size = 0;
        r.state = State.Finality;
        StartFinalityChallenge(p, c, s, e, _steps, to, uniq);
        blocked[task_id] = r.clock + r.timeout;
        return uniq;
    }

    function gameOver(bytes32 id) public returns (bool) {
        Record storage r = records[id];
        if (!(block.number >= r.clock + r.timeout && r.state != State.Finished)) return false;
        require(block.number >= r.clock + r.timeout && r.state != State.Finished);
        if (r.next == r.prover) {
            r.winner = r.challenger;
            rejected[r.task_id] = true;
        }
        else {
            r.winner = r.prover;
            blocked[r.task_id] = 0;
        }
        WinnerSelected(id);
        r.state = State.Finished;
        return true;
    }
    
    function isRejected(uint id) public view returns (bool) {
        return rejected[id];
    }
    
    function blockedTime(uint id) public view returns (uint) {
        return blocked[id] + 5;
    }

    function getIter(bytes32 id) internal view returns (uint it, uint i1, uint i2) {
        Record storage r = records[id];
        it = (r.idx2-r.idx1)/(r.size+1);
        i1 = r.idx1;
        i2 = r.idx2;
    }

    event Reported(bytes32 id, uint idx1, uint idx2, bytes32[] arr);

    function report(bytes32 id, uint i1, uint i2, bytes32[] arr) public returns (bool) {
        Record storage r = records[id];
        require(r.state == State.Running && arr.length == r.size && i1 == r.idx1 && i2 == r.idx2 &&
                msg.sender == r.prover && r.prover == r.next);
        r.clock = block.number;
        blocked[r.task_id] = r.clock + r.timeout;
        uint iter = (r.idx2-r.idx1)/(r.size+1);
        for (uint i = 0; i < arr.length; i++) {
            r.proof[r.idx1+iter*(i+1)] = arr[i];
        }
        r.next = r.challenger;
        Reported(id, i1, i2, arr);
        return true;
    }
    
    function getStateAt(bytes32 id, uint loc) public view returns (bytes32) {
        return records[id].proof[loc];
    }
    
/*    function roundsTest(uint rounds, uint stuff) internal returns (uint it, uint i1, uint i2) {
        bytes32 id = testMake();
        Record storage r = records[id];
        for (uint i = 0; i < rounds; i++) {
            bytes32[] memory arr = new bytes32[](1);
            arr[0] = bytes32(0xffff);
            report(id, r.idx1, r.idx2, arr);
            query(id, r.idx1, r.idx2, stuff % 2);
            stuff = stuff/2;
        }
        return getIter(id);
    } */

    event Queried(bytes32 id, uint idx1, uint idx2);
    event NeedErrorPhases(bytes32 id, uint idx1);

    function query(bytes32 id, uint i1, uint i2, uint num) public {
        Record storage r = records[id];
        require(r.state == State.Running && num <= r.size && i1 == r.idx1 && i2 == r.idx2 &&
                msg.sender == r.challenger && r.challenger == r.next);
        r.clock = block.number;
        blocked[r.task_id] = r.clock + r.timeout;
        uint iter = (r.idx2-r.idx1)/(r.size+1);
        r.idx1 = r.idx1+iter*num;
        // If last segment was selected, do not change last index
        if (num != r.size) r.idx2 = r.idx1+iter;
        if (r.size > r.idx2-r.idx1-1) r.size = r.idx2-r.idx1-1;
        // size eventually becomes zero here
        // check if they disagree on the last state being an error state
        if (r.size == 0 && r.idx2 == r.steps-1 && r.proof[r.idx2] == bytes32(0)) {
            r.next = r.challenger;
            // Challenger will have to post the phases
            NeedErrorPhases(id, r.idx1);
            r.state = State.NeedErrorPhases;
        }
        else {
            r.next = r.prover;
            Queried(id, r.idx1, r.idx2);
            if (r.size == 0) r.state = State.NeedPhases;
        }
    }

    function getStep(bytes32 id, uint idx) public view returns (bytes32) {
        Record storage r = records[id];
        return r.proof[idx];
    }

    event PostedPhases(bytes32 id, uint idx1, bytes32[13] arr);

    function postPhases(bytes32 id, uint i1, bytes32[13] arr) public {
        Record storage r = records[id];
        require(r.state == State.NeedPhases && msg.sender == r.prover && r.next == r.prover && r.idx1 == i1 &&
                r.proof[r.idx1] == arr[0] && r.proof[r.idx1+1] == arr[12] && arr[12] != bytes32(0));
        r.clock = block.number;
        r.state = State.PostedPhases;
        blocked[r.task_id] = r.clock + r.timeout;
        r.result = arr;
        r.next = r.challenger;
        PostedPhases(id, i1, arr);
    }

    event PostedErrorPhases(bytes32 id, uint idx1, bytes32[13] arr);

    function postErrorPhases(bytes32 id, uint i1, bytes32[13] arr) public {
        Record storage r = records[id];
        require(r.state == State.NeedErrorPhases && msg.sender == r.challenger && r.next == r.challenger && r.idx1 == i1 &&
                r.proof[r.idx1] == arr[0] && r.proof[r.idx1+1] == bytes32(0));
        r.clock = block.number;
        blocked[r.task_id] = r.clock + r.timeout;
        r.result = arr;
        r.next = r.prover;
        PostedErrorPhases(id, i1, arr);
        r.state = State.PostedErrorPhases;
    }

    function getResult(bytes32 id)  public view returns (bytes32[13]) {
        Record storage r = records[id];
        return r.result;
    }
    
    event SelectedPhase(bytes32 id, uint idx1, uint phase);
    
    function selectPhase(bytes32 id, uint i1, bytes32 st, uint q) public {
        Record storage r = records[id];
        require(r.state == State.PostedPhases && msg.sender == r.challenger && r.idx1 == i1 && r.result[q] == st &&
                r.next == r.challenger && q < 13);
        r.clock = block.number;
        blocked[r.task_id] = r.clock + r.timeout;
        r.phase = q;
        SelectedPhase(id, i1, q);
        r.next = r.prover;
        r.state = State.SelectedPhase;
    }
    
    function getState(bytes32 id) public view returns (State) {
        return records[id].state;
    }
    
    function getPhase(bytes32 id) public view returns (uint) {
        return records[id].phase;
    }
    
    event SelectedErrorPhase(bytes32 id, uint idx1, uint phase);
    
    function selectErrorPhase(bytes32 id, uint i1, bytes32 st, uint q) public {
        Record storage r = records[id];
        require(r.state == State.PostedErrorPhases && msg.sender == r.prover && r.idx1 == i1 && r.result[q] == st &&
                r.next == r.prover && q < 13);
        r.clock = block.number;
        blocked[r.task_id] = r.clock + r.timeout;
        r.phase = q;
        SelectedErrorPhase(id, i1, q);
        r.next = r.challenger;
        r.state = State.SelectedErrorPhase;
    }
    
    function getWinner(bytes32 id) public view returns (address) {
        return records[id].winner;
    }

    event WinnerSelected(bytes32 id);
    
    function callJudge(bytes32 id, uint i1, uint q,
                        bytes32[] proof,
                        bytes32 vm, bytes32 op, uint[4] regs,
                        bytes32[10] roots, uint[4] pointers) public {
        Record storage r = records[id];
        require(r.state == State.SelectedPhase && r.phase == q && msg.sender == r.prover && r.idx1 == i1 &&
                r.next == r.prover);
        judge.judge(r.result, r.phase, proof, vm, op, regs, roots, pointers);
        WinnerSelected(id);
        r.winner = r.prover;
        blocked[r.task_id] = 0;
        r.state = State.Finished;
    }

    // Challenger has claimed that the state is not final
    function callFinalityJudge(bytes32 id, uint i1,
                        bytes32[] proof,
                        bytes32[10] roots, uint[4] pointers) public {
        Record storage r = records[id];
        require(r.state == State.Finality && msg.sender == r.prover && r.idx1 == i1 &&
                r.next == r.prover);
        // bytes32 fetched_op = 0x0000000000000000000000000000000000000000040606060001000106000000;
        judge.judgeFinality(r.result, proof, roots, pointers);
        WinnerSelected(id);
        r.winner = r.prover;
        blocked[r.task_id] = 0;
        r.state = State.Finished;
    }

    function callErrorJudge(bytes32 id, uint i1, uint q,
                        bytes32[] proof, uint,
                        bytes32 vm, bytes32 op, uint[4] regs,
                        bytes32[10] roots, uint[4] pointers) public {
        Record storage r = records[id];
        require(r.state == State.SelectedErrorPhase && r.phase == q && msg.sender == r.challenger && r.idx1 == i1 &&
                r.next == r.prover);
        judge.judge(r.result, r.phase, proof, vm, op, regs, roots, pointers);
        WinnerSelected(id);
        r.winner = r.challenger;
        rejected[r.task_id] = true;
    }

    function checkFileProof(bytes32 state, bytes32[10] roots, uint[4] pointers, bytes32[] proof, uint loc) public returns (bool) {
        return judge.checkFileProof(state, roots, pointers, proof, loc);
    }
    
    function checkProof(bytes32 hash, bytes32 root, bytes32[] proof, uint loc) public returns (bool) {
        return judge.checkProof(hash, root, proof, loc);
    }

    function calcStateHash(bytes32[10] roots, uint[4] pointers) public returns (bytes32) {
        return judge.calcStateHash(roots, pointers);
    }

/*
    function getInitialHash(bytes32 id) public returns (bytes32) {
        Record storage r = records[id];
        VMParameters storage params = params[id];
        bytes32[] memory roots = new bytes32[](10);
        uint[] memory pointers = new uint[](4);
        
        return judge.calcHash(roots, pointers);
    }
*/

}

