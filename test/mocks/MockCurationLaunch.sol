// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.25;

import {CurationLaunch} from "../../src/CurationLaunch.sol";

contract MockCurationLaunch is CurationLaunch {
    function newFunction() external view returns (string memory) {
        return "I am new Implementation";
    }
}
