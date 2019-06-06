pragma solidity ^0.5.0;

interface IGame {
    function getResult(bytes32 id, address peer1, address peer2) external returns(uint, uint, uint);
}