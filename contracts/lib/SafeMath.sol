pragma solidity ^0.5.0;

library SafeMath {
    function safeAdd(uint a, uint b) internal pure returns (uint sum) {
        sum = a + b;
        require(sum >= a && sum >= b, "unsafe add");
    }

    function safeSub(uint a, uint b) internal pure returns (uint sub) {
        sub = a > b ? a - b : 0;
    }

    /**
     * @notice Calculate the difference and minimum
     */
    function magicSub(uint a, uint b) internal pure returns (uint, uint) {
        return a > b ? (a - b, b) : (b - a, a);
    }
}