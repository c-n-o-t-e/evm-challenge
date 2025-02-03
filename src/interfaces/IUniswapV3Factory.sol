// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IUniswapV3Factory {
    function initialize(uint160 sqrtPriceX96) external;

    function token0() external view returns (address);

    function token1() external view returns (address);

    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
}
