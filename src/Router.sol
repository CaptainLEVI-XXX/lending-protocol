// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAccessRegistry} from "@qiro/interfaces/IAccessRegistry.sol";
import {CustomRevert} from "@qiro/libraries/CustomRevert.sol";
import {Roles} from "@qiro/helper/Roles.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILendingVault} from "@qiro/interfaces/ILendingVault.sol";
import {IBorrowVault} from "@qiro/interfaces/IBorrowVault.sol";
import {Lock} from "@qiro/libraries/Lock.sol";

/// @title VaultRouter
/// @notice Main router contract for handling deposits, withdrawals, and borrowing functionality
/// @dev This contract serves as the central hub for all vault operations, providing a secure interface
///      for users to interact with lending and borrowing vaults.
contract VaultRouter is Roles {
    using CustomRevert for bytes4;
    using SafeTransferLib for address;
    using Lock for *;

    /// @dev Constructor to initialize the contract with an access registry address
    /// @param _accessRegistry The address of the access registry
    constructor(address _accessRegistry) {
        initializeRoles(_accessRegistry);
    }

    /// @dev Custom error definitions for the router contract
    error AssetNotSupported();
    error InvalidAmount();
    error InvalidAddress();
    error RouterLocked();

    /// @dev Struct to store lending vault information
    /// @param vaultAddress Address of the lending vault
    /// @param minDepositAmount Minimum amount that can be deposited
    /// @param maxDepositAmount Maximum amount that can be deposited
    /// @param isPaused Whether the vault is paused
    struct LendingVaultInfo {
        address vaultAddress;
        uint256 minDepositAmount;
        uint256 maxDepositAmount;
        bool isPaused;
    }

    /// @dev Struct to store borrowing vault information
    /// @param vaultAddress Address of the borrowing vault
    /// @param minLoanAmount Minimum loan amount
    /// @param maxLoanAmount Maximum loan amount
    /// @param isPaused Whether the vault is paused
    struct BorrowVaultInfo {
        address vaultAddress;
        uint256 minLoanAmount;
        uint256 maxLoanAmount;
        uint256 maxLoanDuration;
        uint256 minLoanDuration;
        bool isPaused;
    }

    /// @dev Mappings to store vault information for each asset
    mapping(address => LendingVaultInfo) public lendingVaults;
    mapping(address => BorrowVaultInfo) public borrowVaults;

    /// @dev Modifier to prevent reentrancy attacks
    modifier nonReentrant() {
        if (Lock.isUnlocked()) RouterLocked.selector.revertWith();
        Lock.unlock();
        _;
        Lock.lock();
    }

    /// @notice Set lending vault information for an asset
    /// @dev Only callable by admin. Updates the lending vault configuration for a specific asset
    /// @param _asset The address of the asset
    /// @param _vaultInfo The lending vault configuration
    function setLendingVault(address _asset, LendingVaultInfo calldata _vaultInfo) external onlyAdmin {
        lendingVaults[_asset] = _vaultInfo;
    }

    /// @notice Set borrowing vault information for an asset
    /// @dev Only callable by admin. Updates the borrowing vault configuration for a specific asset
    /// @param _asset The address of the asset
    /// @param _vaultInfo The borrowing vault configuration
    function setBorrowVault(address _asset, BorrowVaultInfo calldata _vaultInfo) external onlyAdmin {
        borrowVaults[_asset] = _vaultInfo;
    }

    /// @notice Get lending vault information for an asset
    /// @dev Retrieves the lending vault configuration for a specific asset
    /// @param _asset The address of the asset
    /// @return The lending vault information
    function getLendingVault(address _asset) public view returns (LendingVaultInfo memory) {
        isLendingVaultSupported(_asset);
        return lendingVaults[_asset];
    }

    /// @notice Get borrowing vault information for an asset
    /// @dev Retrieves the borrowing vault configuration for a specific asset
    /// @param _asset The address of the asset
    /// @return The borrowing vault information
    function getBorrowVault(address _asset) public view returns (BorrowVaultInfo memory) {
        isBorrowVaultSupported(_asset);
        return borrowVaults[_asset];
    }

    /// @notice Deposit tokens into a lending vault
    /// @dev Users can deposit tokens into their chosen lending vault
    /// @param _asset The address of the asset being deposited
    /// @param _amount The amount of tokens to deposit
    /// @param _reciever The address receiving the shares
    /// @return shares The number of shares received
    function deposit(address _asset, uint256 _amount, address _reciever)
        external
        nonReentrant
        returns (uint256 shares)
    {
        LendingVaultInfo memory vaultInfo = getLendingVault(_asset);
        if (_amount < vaultInfo.minDepositAmount || _amount > vaultInfo.maxDepositAmount) {
            InvalidAmount.selector.revertWith();
        }
        if (_reciever == address(0)) InvalidAddress.selector.revertWith();

        _asset.safeTransferFrom(msg.sender, address(this), _amount);
        _asset.safeApprove(vaultInfo.vaultAddress, _amount);

        shares = ILendingVault(vaultInfo.vaultAddress).deposit(_amount, _reciever);
    }

    /// @notice Withdraw tokens from a lending vault
    /// @dev Users can withdraw their tokens from a lending vault
    /// @param _asset The address of the asset being withdrawn
    /// @param _amount The amount of tokens to withdraw
    /// @param _reciever The address receiving the withdrawn tokens
    /// @param owner The owner of the shares
    /// @return asset The amount of tokens withdrawn
    function withdraw(address _asset, uint256 _amount, address _reciever, address owner)
        external
        nonReentrant
        returns (uint256 asset)
    {
        LendingVaultInfo memory vaultInfo = getLendingVault(_asset);
        if (_reciever == address(0)) InvalidAddress.selector.revertWith();
        if (_reciever != owner) InvalidAddress.selector.revertWith();
        asset = ILendingVault(vaultInfo.vaultAddress).withdraw(_amount, _reciever, owner);
    }

    /// @notice Request a loan from a borrowing vault
    /// @dev Only whitelisted borrowers can request loans
    /// @param _asset The address of the asset being borrowed
    /// @param _amount The amount of tokens to borrow
    /// @param _duration The duration of the loan
    /// @return requestId The ID of the loan request
    function requestBorrow(address _asset, uint256 _amount, uint256 _duration)
        external
        onlyWhitelistedBorrower
        nonReentrant
        returns (uint256 requestId)
    {
        BorrowVaultInfo memory vaultInfo = getBorrowVault(_asset);
        if (_amount < vaultInfo.minLoanAmount || _amount > vaultInfo.maxLoanAmount) InvalidAmount.selector.revertWith();
        if (_duration < vaultInfo.minLoanDuration || _duration > vaultInfo.maxLoanDuration) {
            InvalidAmount.selector.revertWith();
        }
        requestId = IBorrowVault(vaultInfo.vaultAddress).requestBorrow(_amount, _duration, msg.sender);
    }

    /// @notice Make a payment on a loan
    /// @dev Users can make payments on their loans
    /// @param _asset The address of the asset being paid
    /// @param _borrower The address of the borrower
    function makePayment(address _asset, address _borrower) external nonReentrant {
        BorrowVaultInfo memory vaultInfo = getBorrowVault(_asset);
        IBorrowVault vaultDispatcher = IBorrowVault(vaultInfo.vaultAddress);
        (,,, uint256 monthlyPayment,,,) = vaultDispatcher.getLoanDetails(_borrower);

        _asset.safeTransferFrom(msg.sender, address(this), monthlyPayment);
        _asset.safeApprove(vaultInfo.vaultAddress, monthlyPayment);
        vaultDispatcher.makePayment(_borrower);
    }

    /// @notice Pay off an entire loan
    /// @dev Users can pay off their entire loan balance
    /// @param _asset The address of the asset being paid
    /// @param _borrower The address of the borrower
    function payoffLoan(address _asset, address _borrower) external nonReentrant {
        BorrowVaultInfo memory vaultInfo = getBorrowVault(_asset);
        IBorrowVault vaultDispatcher = IBorrowVault(vaultInfo.vaultAddress);
        uint256 payoffAmount = vaultDispatcher.getPayoffAmount(_borrower);
        _asset.safeTransferFrom(msg.sender, address(this), payoffAmount);
        _asset.safeApprove(vaultInfo.vaultAddress, payoffAmount);
        vaultDispatcher.payoffLoan(_borrower);
    }

    /// @dev Internal function to check if lending vault is supported for an asset
    /// @param _asset The address of the asset
    /// @return Whether the lending vault is supported
    function isLendingVaultSupported(address _asset) internal view returns (bool) {
        address vaultAddress = lendingVaults[_asset].vaultAddress;
        if (vaultAddress == address(0)) AssetNotSupported.selector.revertWith();
        return true;
    }

    /// @dev Internal function to check if borrowing vault is supported for an asset
    /// @param _asset The address of the asset
    /// @return Whether the borrowing vault is supported
    function isBorrowVaultSupported(address _asset) internal view returns (bool) {
        address vaultAddress = borrowVaults[_asset].vaultAddress;
        if (vaultAddress == address(0)) AssetNotSupported.selector.revertWith();
        return true;
    }
}
