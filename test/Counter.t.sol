// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {AccessRegistry} from "../src/AccessRegistry.sol";
import {LendingVault} from "../src/LendingVault.sol";
import {BorrowVault} from "../src/BorrowVault.sol";
import {MockERC20} from "../mock/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BaseTest is Test {
    AccessRegistry public accessRegistry;
    LendingVault public lendingVault;
    BorrowVault public borrowVault;
    MockERC20 public asset;
    address public admin = makeAddr("admin");
    address public signer1 = makeAddr("signer1");
    address public signer2 = makeAddr("signer2");
    address public signer3 = makeAddr("signer3");
    address public depositer = makeAddr("depositer");
    address public whitelistedBorrower = makeAddr("whitelistedBorrower");

    function setup() public {
        asset = new MockERC20("ETH", "ETH");
        accessRegistry = new AccessRegistry(admin);
        lendingVault = new LendingVault(IERC20(asset), "LETH", "LETH", address(accessRegistry));
        borrowVault = new BorrowVault("BETH", "BETH", address(accessRegistry), address(lendingVault), address(asset));
        _setupConfig();
    }

    function _setupConfig() internal {
        accessRegistry.grantRole(ADMIN_ROLE, admin);

        accessRegistry.grantRole(MULTISIG_SIGNER_ROLE, signer1);
        accessRegistry.grantRole(MULTISIG_SIGNER_ROLE, signer2);
        accessRegistry.grantRole(MULTISIG_SIGNER_ROLE, signer3);

        accessRegistry.grantRole(WHITELISTED_BORROWER_ROLE, whitelistedBorrower);

        accessRegistry.grantRole(PROTOCOL_LEVEL_ROLE, address(lendingVault));
        accessRegistry.grantRole(PROTOCOL_LEVEL_ROLE, address(borrowVault));

        asset.mint(depositer, 1000_000 * 1e18);
    }

    function testDeposit() public {
        vm.startPrank(depositer);
        asset.approve(address(lendingVault), 1000 * 1e18);
        lendingVault.deposit(1000 * 1e18);
        vm.stopPrank();
    }

    function testBorrow() public {}

    function testWithdraw() public {}
}
