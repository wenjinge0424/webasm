pragma solidity ^0.4.16;

import "./fs.sol";

interface Interactive {
    function make(address p, address c, bytes32 s, bytes32 e, uint256 steps,
        uint256 par, uint to) public returns (bytes32);
    function makeFinality(address p, address c, bytes32 s, bytes32 e, uint256 _steps, uint to) public returns (bytes32);
}

interface Callback {
    function solved(bytes32 result) public;
}

contract Tasks is Filesystem {
    
    event Posted(address giver, bytes32 hash, string file, string input, int input_file, uint id);
    event Solved(uint id, bytes32 hash, uint steps, bytes32 init, string file, string input);
    
    Interactive iactive;
    
    function Tasks(address contr) public {
        iactive = Interactive(contr);
    }
    
    function getInteractive() public view returns (address) {
        return address(iactive);
    }
    
    struct Task {
        address giver;
        bytes32 init;
        string file; // currently ipfs hash
        string input; // also ipfs hash
        int input_file; // get file from the filesystem
        
        address solver;
        bytes32 result;
        uint steps;
        uint state;
    }
    
    Task[] public tasks;
    
    mapping (bytes32 => uint) challenges;
    
    function add(bytes32 init, string file, string input) public returns (uint) {
        tasks.push(Task(msg.sender, init, file, input, -1, 0, 0, 0, 0));
        Posted(msg.sender, init, file, input, -1, tasks.length-1);
        return tasks.length-1;
    }
    
    // Perhaps it should lock the file?
    function addWithFile(bytes32 init, string file, uint input_file) public returns (uint) {
        tasks.push(Task(msg.sender, init, file, "", int(input_file), 0, 0, 0, 0));
        Posted(msg.sender, init, file, "", int(input_file), tasks.length-1);
        return tasks.length-1;
    }

    function solve(uint id, bytes32 result, uint steps) public {
        require(tasks[id].solver == 0);
        tasks[id].solver = msg.sender;
        tasks[id].result = result;
        tasks[id].steps = steps;
        tasks[id].state = 1;
        Solved(id, result, steps, tasks[id].init, tasks[id].file, tasks[id].input);
    }

    function challenge(uint id) public {
        Task storage t = tasks[id];
        require(t.state == 1);
        bytes32 uniq = iactive.make(t.solver, msg.sender, t.init, t.result, t.steps, 1, 10);
        challenges[uniq] = id;
    }

    function challengeFinality(uint id) public {
        Task storage t = tasks[id];
        require(t.state == 1);
        bytes32 uniq = iactive.makeFinality(t.solver, msg.sender, t.init, t.result, t.steps, 10);
        challenges[uniq] = id;
    }
    
    function queryChallenge(bytes32 uniq) constant public returns (uint) {
        return challenges[uniq];
    }
    
    function finalize(uint id) public {
        Task storage t = tasks[id];
        require(t.state == 1);
        t.state = 3;
        Callback(t.giver).solved(t.result);
    }

}

