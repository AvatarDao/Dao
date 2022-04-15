// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TetherUSD is ERC20 {
    constructor() ERC20("Tether USD", "USDT") {
        _mint(msg.sender, 3000000000 * 10 ** decimals());
    }
}