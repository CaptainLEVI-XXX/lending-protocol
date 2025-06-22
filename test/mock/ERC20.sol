// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "@solady/tokens/ERC20.sol";

contract MockERC20 is ERC20 {

    function name() public pure override returns (string memory) {
        return "MockERC20";
    }

    function symbol() public pure override returns (string memory) {
        return "MOCK";  
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }
}
