// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (utils/math/SafeMath.sol)

pragma solidity =0.7.6;

library SafeMath128 {
    
    function add(uint128 a, uint128 b) internal pure returns (uint128) {
        return a + b;
    }

    function sub(uint128 a, uint128 b) internal pure returns (uint128) {
        return a - b;
    }

    function mul(uint128 a, uint128 b) internal pure returns (uint128) {
        return a * b;
    }

    function div(uint128 a, uint128 b) internal pure returns (uint128) {
        return a / b;
    }

    function mod(uint128 a, uint128 b) internal pure returns (uint128) {
        return a % b;
    }
}