// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "oz/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function testExcludeContractForCoverage() external {}
}
