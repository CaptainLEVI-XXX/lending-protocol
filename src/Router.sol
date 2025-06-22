// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccessRegistry} from "./interfaces/IAccessRegistry.sol";
import {CustomRevert} from "./libraries/CustomRevert.sol";
import {Roles} from "./helper/Roles.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILendingVault} from "./interfaces/ILendingVault.sol";
import {IBorrowVault} from "./interfaces/IBorrowVault.sol";
import {Lock} from "./libraries/Lock.sol";

contract VaultRouter is Roles {
    using CustomRevert for bytes4;
    using SafeERC20 for IERC20;
    using Lock for *;

    constructor(address _accessRegistry) Roles(_accessRegistry) {
    }

    error AssetNotSupported();
    error InvalidAmount();
    error InvalidAddress();
    error RouterLocked();

    struct LendingVaultInfo {
        address vaultAddress;
        uint256 minDepositAmount;
        uint256 maxDepositAmount;
        bool isPaused;
    }

    struct BorrowVaultInfo {
        address vaultAddress;
        uint256 minLoanAmount;
        uint256 maxLoanAmount;
        bool isPaused;
    }

    mapping(address asset => LendingVaultInfo) public lendingVaults;
    mapping(address asset => BorrowVaultInfo) public borrowVaults;

    modifier nonReentrant() {
        if (Lock.isUnlocked()) RouterLocked.selector.revertWith();
        Lock.unlock();
        _;
        Lock.lock();
    }



    function addLendingVault(address _asset, LendingVaultInfo calldata _vaultInfo) external onlyAdmin {
        lendingVaults[_asset] = _vaultInfo;
    }

    function addBorrowVault(address _asset, BorrowVaultInfo calldata _vaultInfo) external onlyAdmin {
        borrowVaults[_asset] = _vaultInfo;
    }

    function getLendingVault(address _asset) public view returns (LendingVaultInfo memory) {
        isLendingVaultSupported(_asset);
        return lendingVaults[_asset];
    }

    function getBorrowVault(address _asset) public view returns (BorrowVaultInfo memory) {
        isBorrowVaultSupported(_asset);
        return borrowVaults[_asset];
    }

    function deposit(address _asset, uint256 _amount, address _reciever) external returns (uint256 shares) {
        LendingVaultInfo memory vaultInfo = getLendingVault(_asset);
        if (_amount < vaultInfo.minDepositAmount || _amount > vaultInfo.maxDepositAmount) {
            InvalidAmount.selector.revertWith();
        }
        if (_reciever == address(0)) InvalidAddress.selector.revertWith();

        IERC20 assetDispatcher = IERC20(_asset);
        assetDispatcher.safeTransferFrom(msg.sender, address(this), _amount);
        assetDispatcher.forceApprove(vaultInfo.vaultAddress, _amount);

        shares = ILendingVault(vaultInfo.vaultAddress).deposit(_amount, _reciever);
    }

    function withdraw(address _asset, uint256 _amount, address _reciever) external returns (uint256 asset) {
        LendingVaultInfo memory vaultInfo = getLendingVault(_asset);
        if (_reciever == address(0)) InvalidAddress.selector.revertWith();

        asset = ILendingVault(vaultInfo.vaultAddress).withdraw(_amount, _reciever, _reciever);
    }

    function requestBorrow(address _asset, uint256 _amount)
        external
        onlyWhitelistedBorrower
        returns (uint256 requestId)
    {
        BorrowVaultInfo memory vaultInfo = getBorrowVault(_asset);
        if (_amount < vaultInfo.minLoanAmount || _amount > vaultInfo.maxLoanAmount) InvalidAmount.selector.revertWith();
        requestId = IBorrowVault(vaultInfo.vaultAddress).requestBorrow(_amount, msg.sender);
    }

    function repayBorrow(address _asset, uint256 _amount) external onlyWhitelistedBorrower {
        BorrowVaultInfo memory vaultInfo = getBorrowVault(_asset);

        IERC20 assetDispatcher = IERC20(_asset);
        assetDispatcher.safeTransferFrom(msg.sender, address(this), _amount);
        assetDispatcher.forceApprove(vaultInfo.vaultAddress, _amount);
        IBorrowVault(vaultInfo.vaultAddress).repay(_amount, msg.sender);
    }

    function isLendingVaultSupported(address _asset) internal view returns (bool) {
        address vaultAddress = lendingVaults[_asset].vaultAddress;
        if (vaultAddress == address(0)) AssetNotSupported.selector.revertWith();
        return true;
    }

    function isBorrowVaultSupported(address _asset) internal view returns (bool) {
        address vaultAddress = borrowVaults[_asset].vaultAddress;
        if (vaultAddress == address(0)) AssetNotSupported.selector.revertWith();
        return true;
    }
}
