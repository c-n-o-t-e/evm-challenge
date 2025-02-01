// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ICurationToken {
    function burn(uint256 amount) external;
    function mint(address to, uint256 amount) external;
}
