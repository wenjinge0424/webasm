pragma solidity ^0.4.4;

contract DepositsManager {

    mapping(address => uint) public deposits;

    event DepositMade(address who, uint amount);
    event DepositWithdrawn(address who, uint amount);

    // @dev – the constructor
    constructor() public {
    }

    // @dev – returns an account's deposit
    // @param who – the account's address.
    // @return – the account's deposit.
    function getDeposit(address who) constant public returns (uint) {
        return deposits[who];
    }

    // @dev – allows a user to deposit eth.
    // @return – the user's updated deposit amount.
    function makeDeposit() public payable returns (uint) {
        deposits[msg.sender] += msg.value;
        emit DepositMade(msg.sender, msg.value);
        return deposits[msg.sender];
    }

    // @dev – allows a user to withdraw eth from their deposit.
    // @param amount – how much eth to withdraw
    // @return – the user's updated deposit amount.
    function withdrawDeposit(uint amount) public returns (uint) {
        require(deposits[msg.sender] > amount);

        deposits[msg.sender] -= amount;
        msg.sender.transfer(amount);

        emit DepositWithdrawn(msg.sender, amount);
        return deposits[msg.sender];
    }
    
    function addDeposit(address a, uint d) internal {
        deposits[a] += d;
    }

    function subDeposit(address a, uint d) internal {
        require(deposits[a] >= d);
        deposits[a] -= d;
    }
    
    function transferDeposit(address a, address b, uint amount) internal {
        addDeposit(b, amount);
        subDeposit(a, amount);
    }

}