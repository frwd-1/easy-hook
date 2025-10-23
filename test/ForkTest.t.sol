// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
 
import "forge-std/Test.sol";
 
interface IERC20 {
    function balanceOf(address account) external view returns (uint);
}
 
contract ForkTest is Test {
    
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDC_WHALE = 0xadBbE373B5b5F72C59c0311cFfBded51f0C5F434;
 
    uint forkId;
 
    // modifier to create and select a fork from MAINNET_RPC_URL env var
    modifier forked() {
        forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(forkId);
        vm.rollFork(37223320);
        _;
    }

    function testUSDCBalanceForked() public forked {
        // Deploy a new USDC contract
        deployCodeTo('USDC.sol', '', USDC);

        uint balance = IERC20(USDC).balanceOf(USDC_WHALE);
        console.log("Whale balance (USDC):", balance / 1e6);

        assertEq(balance, 123, "Whale should have large balance");
    }
}