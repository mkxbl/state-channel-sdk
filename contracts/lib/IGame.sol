pragma solidity ^0.5.0;

interface IGame {
    function getResult(bytes32 id) external returns(uint, uint);
}