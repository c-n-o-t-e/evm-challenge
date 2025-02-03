// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {NewLaunch} from "../../src/NewLaunch.sol";

contract MockNewLaunch is NewLaunch {
    function newFunction() external view returns (string memory) {
        return "I am new Implementation";
    }
}
