pragma solidity ^0.5.0;

interface IGame {
    function getResult(bytes32, address, address) external returns(uint, uint, uint);
}