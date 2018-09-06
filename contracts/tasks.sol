pragma solidity ^0.4.16;

import "./DepositsManager.sol";
import "./interactive.sol";
import "./fs.sol";
import "./IGameMaker.sol";

interface Callback {
    function solved(uint id, bytes32[] files) external;
    function rejected(uint id) external;
}

contract Tasks is DepositsManager {

    uint constant DEPOSIT = 0.01 ether;
    uint constant TIMEOUT = 50;

    enum CodeType {
        WAST,
        WASM,
        INTERNAL
    }

    enum Storage {
        IPFS,
        BLOCKCHAIN
    }

    event Posted(address giver, bytes32 hash, CodeType ct, Storage cs, string stor, uint id, uint deposit);
    event RePosted(address giver, bytes32 hash, CodeType ct, Storage cs, string stor, uint id, uint deposit);
    event Solved(uint id, bytes32 hash, bytes32 init, CodeType ct, Storage cs, string stor, address solver, uint deposit);
    event Finalized(uint id);

    Interactive iactive;
    Filesystem fs;

    constructor(address disputeResolutionLayer, address fileSystem) public {
        iactive = Interactive(disputeResolutionLayer);
        fs = Filesystem(fileSystem);
    }

    function getInteractive() public view returns (address) {
        return address(iactive);
    }

    struct RequiredFile {
       bytes32 name_hash;
       Storage file_storage;
       bytes32 file_id;
    }

    struct IO {
       bytes32 name;
       bytes32 size;
       bytes32 data;
       
       RequiredFile[] uploads;
    }

    struct VMParameters {
        uint8 stack_size;
        uint8 memory_size;
        uint8 call_size;
        uint8 globals_size;
        uint8 table_size;
    }

    struct Task {
        address giver;
        bytes32 init; // includes code and input roots, the output should be similar
        string stor;
        
        CodeType code_type;
        Storage storage_type;
        
        uint state;

        address solver;
        bytes32 result;
        
        bytes32 output_file;
        
        bool good; // has the file been loaded
        uint blocked; // how long we have to wait to accept solution
        
        bytes32[] challenges;	
    }

    Task[] public tasks;
    VMParameters[] params;
    IO[] io_roots;

    mapping (bytes32 => uint) challenges;

    function defaultParameters(uint id) internal {
        VMParameters storage param = params[id];
        param.stack_size = 14;
        param.memory_size = 16;
        param.globals_size = 8;
        param.table_size = 8;
        param.call_size = 10;
    }

    function add(bytes32 init, CodeType ct, Storage cs, string stor) public returns (uint) {
        uint id = tasks.length;
        tasks.length++;
        params.length++;
        io_roots.length++;
        Task storage t = tasks[id];
        t.giver = msg.sender;
        t.init = init;
        t.stor = stor;
        // t.good = true;
        t.code_type = ct;
        t.storage_type = cs;
        defaultParameters(id);
        // emit Posted(msg.sender, init, ct, cs, stor, id, DEPOSIT);
        commit(id);
        return id;
    }

    function commit(uint id) public {
        Task storage t1 = tasks[id];
        Task2 storage t2 = tasks2[id];
        require (msg.sender == t1.giver);
        t2.good = true;
        emit Posted(t1.giver, t1.init, t1.code_type, t1.storage_type, t1.stor, id, DEPOSIT);
    }

    function addWithParameters(bytes32 init, CodeType ct, Storage cs, string stor, uint8 stack, uint8 mem, uint8 globals, uint8 table, uint8 call) public returns (uint) {
        uint id = tasks.length;
        tasks.length++;
        params.length++;
        io_roots.length++;
        Task storage t = tasks[id];
        t.giver = msg.sender;
        t.init = init;
        t.stor = stor;
        // t.good = true;
        t.code_type = ct;
        t.storage_type = cs;
        
        VMParameters storage param = params[id];
        param.stack_size = stack;
        param.memory_size = mem;
        param.globals_size = globals;
        param.table_size = table;
        param.call_size = call;
        // emit Posted(msg.sender, init, ct, cs, stor, id, DEPOSIT);
        return id;
    }

    // Make sure they won't be required after the task has been posted already
    function requireFile(uint id, bytes32 hash, Storage st) public {
        Task storage t1 = tasks[id];
        Task2 storage t2 = tasks2[id];
        require (!t2.good && msg.sender == t1.giver);
        IO storage io = io_roots[id];
        io.uploads.push(RequiredFile(hash, st, 0));
    }

    function getUploadNames(uint id) public view returns (bytes32[]) {
        RequiredFile[] storage lst = io_roots[id].uploads;
        bytes32[] memory arr = new bytes32[](lst.length);
        for (uint i = 0; i < arr.length; i++) arr[i] = lst[i].name_hash;
        return arr;
        
    }

    function getUploadTypes(uint id) public view returns (Storage[]) {
        RequiredFile[] storage lst = io_roots[id].uploads;
        Storage[] memory arr = new Storage[](lst.length);
        for (uint i = 0; i < arr.length; i++) arr[i] = lst[i].file_storage;
        return arr;
    }

    function taskInfo(uint unq) public view returns (address giver, bytes32 hash, CodeType ct, Storage cs, string stor, uint id) {
        Task storage t = tasks[unq];
        return (t.giver, t.init, t.code_type, t.storage_type, t.stor, unq);
    }

    function getVMParameters(uint id) public view returns (uint8 stack, uint8 mem, uint8 globals, uint8 table, uint8 call) {
        VMParameters storage param = params[id];
        stack = param.stack_size;
        mem = param.memory_size;
        globals = param.globals_size;
        table = param.table_size;
        call = param.call_size;
    }
    
    function nextTask() public view returns (uint) {
        return tasks.length;
    }

    function getSolver(uint id) public view returns (address) {
        return tasks[id].solver;
    }

    function solveIO(uint id, bytes32 code, bytes32 size, bytes32 name, bytes32 data) public returns (bool) {
        Task storage t = tasks[id];
        IO storage io = io_roots[id];
        require(t.solver == 0 && t.good);
        
        io.size = size;
        io.name = name;
        io.data = data;
        t.solver = msg.sender;
        t.result = keccak256(abi.encodePacked(code, size, name, data));
        t.state = 1;
        t.blocked = block.number + TIMEOUT;
        emit Solved(id, t.result, t.init, t.code_type, t.storage_type, t.stor, t.solver, DEPOSIT);
        subDeposit(msg.sender, DEPOSIT);
        return true;
    }

    function solutionInfo(uint unq) public view returns (uint id, bytes32 hash, bytes32 init, CodeType ct, Storage cs, string stor, address solver) {
        Task storage t = tasks[unq];
        return (unq, t.result, t.init, t.code_type, t.storage_type, t.stor, t.solver);
    }

    /*
    function getCodeType(uint id) public view returns (CodeType) {
        return tasks[id].code_type;
    }

    function getCodeStorage(uint id) public view returns (Storage) {
        // return tasks[id].code_storage;
    }
    */

    function challenge(uint id) public {
        Task storage t = tasks[id];
        // VMParameters storage p = params[id];
        require(t.state == 1);
        bytes32 uniq = IGameMaker(iactive).make(id, t.solver, msg.sender, t.init, t.result, 1, TIMEOUT);
        challenges[uniq] = id;
        t.challenges.push(uniq);
        subDeposit(msg.sender, DEPOSIT);
    }

    function queryChallenge(bytes32 uniq) constant public returns (uint) {
        return challenges[uniq];
    }

    function getChallenges(uint id) public view returns (bytes32[]) {
        return tasks[id].challenges;
    }

    function uploadFile(uint id, uint num, bytes32 file_id, bytes32[] name_proof, bytes32[] data_proof, uint file_num) public returns (bool) {
        IO storage io = io_roots[id];
        RequiredFile storage file = io.uploads[num];
        if (!iactive.checkProof(fs.getRoot(file_id), io.data, data_proof, file_num) || !iactive.checkProof(fs.getNameHash(file_id), io.name, name_proof, file_num)) return false;
        require(iactive.checkProof(fs.getRoot(file_id), io.data, data_proof, file_num));
        require(iactive.checkProof(fs.getNameHash(file_id), io.name, name_proof, file_num));
        
        file.file_id = file_id;
        return true;
    }

    function finalizeTask(uint id) public returns (bool) {
        Task storage t = tasks[id];
        IO storage io = io_roots[id];
        if (t.state != 1 || t.blocked >= block.number || iactive.isRejected(id) || iactive.blockedTime(id) >= block.number) return false;
        // if (!(t.state == 1 && t2.blocked < block.number && !iactive.isRejected(id) && iactive.blockedTime(id) < block.number)) return false;
        
        // require(t.state == 1 && t2.blocked < block.number && !iactive.isRejected(id) && iactive.blockedTime(id) < block.number);
        t.state = 3;
        
        bytes32[] memory files = new bytes32[](io.uploads.length);
        for (uint i = 0; i < io.uploads.length; i++) {
           if (io.uploads[i].file_id == 0) return false;
           // require(io.uploads[i].file_id != 0);
           files[i] = io.uploads[i].file_id;
        }
        
        if (files.length > 0) Callback(t.giver).solved(id, files);
        
        emit Finalized(id);
        addDeposit(t.solver, DEPOSIT);
        
        return true;
    }
    
    function claimDeposit(bytes32 cid) public returns (address) {
        uint id = iactive.getTask(cid);
        require(iactive.isRejected(id));
        address challenger = iactive.getChallenger(cid);
        require(challenger != 0);
        addDeposit(challenger, DEPOSIT);
        iactive.deleteChallenge(cid);
        Task2 storage t2 = tasks2[id];
        Task storage t1 = tasks[id];
        t2.solver = 0;
        t2.good = true;
        t1.state = 0;
        emit RePosted(t1.giver, t1.init, t1.code_type, t1.storage_type, t1.stor, id, DEPOSIT);
        return challenger;
    }

    uint tick_var;

    // For testing, mine this to create new block
    function tick() public  {
        tick_var++;
    }

}
