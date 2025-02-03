// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LaunchFactory} from "../../src/LaunchFactory.sol";

contract MockLaunchFactory is LaunchFactory {
    function newFunction() external view returns (string memory) {
        return "I am new Implementation";
    }
}
