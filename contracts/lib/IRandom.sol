pragma solidity ^0.5.0;

interface IRandom {
    function getRandom(bytes32 id) external returns(uint, bytes32, address);
}