// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";


contract USDC {
    function balanceOf(address _account) external view returns (uint256) {
        console.log('balanceOf _account', _account);
        return 123;
    }
}