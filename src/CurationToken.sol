// SPDX-License-Identifier: Unlicense
pragma solidity =0.8.25;

import "oz/contracts/token/ERC20/ERC20.sol";

// Demo Token
contract CurationToken is ERC20 {
    constructor() ERC20("CurationToken", "CT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
