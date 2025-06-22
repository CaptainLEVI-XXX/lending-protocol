// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccessRegistry} from "./interfaces/IAccessRegistry.sol";
import {CustomRevert} from "./libraries/CustomRevert.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Roles} from "./helper/Roles.sol";

/**
 * @title LendingVault
 * @dev ERC-4626 compliant vault for deposits and withdrawals
 * @notice This vault accepts deposits and allocates funds to borrow vaults
 */
contract LendingVault is ERC4626, UUPSUpgradeable, Roles {
    using SafeERC20 for IERC20;
    using CustomRevert for bytes4;

    // Borrow vaults that can request funds
    mapping(address => bool) public authorizedBorrowVaults;

    // Track funds allocated to each borrow vault
    mapping(address => uint256) public borrowVaultAllocations;

    // Total funds allocated across all borrow vaults
    uint256 public totalAllocated;

    //error
    error InvalidAddress();
    error AlreadyAuthorized();
    error InsufficientLiquidity();
    error InvalidAmount();
    error NotAdmin();

    // Events
    event BorrowVaultAuthorized(address indexed borrowVault);
    event BorrowVaultDeauthorized(address indexed borrowVault);
    event FundsAllocated(address indexed borrowVault, uint256 amount);
    event FundsReturned(address indexed borrowVault, uint256 principal, uint256 interest);
    event InterestAccrued(uint256 amount);


    /**
     * @dev Constructor
     * @param _asset Underlying ERC20 token
     * @param _name Vault share token name
     * @param _symbol Vault share token symbol
     * @param _accessRegistry Access control registry
     */
    constructor(IERC20 _asset, string memory _name, string memory _symbol, address _accessRegistry)
        ERC20(_name, _symbol)
        ERC4626(_asset) Roles(_accessRegistry)
    {
        if (_accessRegistry == address(0)) InvalidAddress.selector.revertWith();
    }

    /**
     * @dev Allocate funds to a borrow vault
     * @param amount Amount to allocate
     * @return success True if allocation succeeded
     */
    function allocateFunds(uint256 amount) external onlyProtocolLevel returns (bool success) {
        if (amount == 0) InvalidAmount.selector.revertWith();

        uint256 available = availableLiquidity();
        if (amount > available) InsufficientLiquidity.selector.revertWith();

        borrowVaultAllocations[msg.sender] += amount;
        totalAllocated += amount;

        IERC20(asset()).safeTransfer(msg.sender, amount);

        emit FundsAllocated(msg.sender, amount);
        return true;
    }

    /**
     * @dev Return funds from a borrow vault
     * @param principal Principal amount being returned
     * @param interest Interest amount being paid
     */
    function returnFunds(uint256 principal, uint256 interest) external onlyProtocolLevel {
        if (principal > borrowVaultAllocations[msg.sender]) InvalidAmount.selector.revertWith();

        uint256 totalReturn = principal + interest;
        if (totalReturn == 0) InvalidAmount.selector.revertWith();

        // Update allocations
        borrowVaultAllocations[msg.sender] -= principal;
        totalAllocated -= principal;

        // Transfer funds back
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), totalReturn);

        // Interest increases the vault's assets, benefiting all shareholders
        if (interest > 0) {
            emit InterestAccrued(interest);
        }

        emit FundsReturned(msg.sender, principal, interest);
    }

    /**
     * @dev Get available liquidity for lending
     * @return Available funds not allocated to borrow vaults
     */
    function availableLiquidity() public view returns (uint256) {
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));
        return vaultBalance; // All balance is available since allocated funds are transferred out
    }

    /**
     * @dev Total assets under management (including allocated funds)
     * @return Total assets
     */
    function totalAssets() public view virtual override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + totalAllocated;
    }

    /**
     * @dev Override to ensure sufficient liquidity for withdrawals
     */
    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        uint256 assets = convertToAssets(balanceOf(owner));
        uint256 available = availableLiquidity();
        return assets > available ? available : assets;
    }

    /**
     * @dev Override to ensure sufficient liquidity for redemptions
     */
    function maxRedeem(address owner) public view virtual override returns (uint256) {
        uint256 shares = balanceOf(owner);
        uint256 assets = convertToAssets(shares);
        uint256 available = availableLiquidity();

        if (assets > available) {
            // Calculate shares that can be redeemed with available liquidity
            return convertToShares(available);
        }
        return shares;
    }

    /**
     * @dev Get vault statistics
     */
    function getVaultStats()
        external
        view
        returns (uint256 totalAssetsManaged, uint256 totalAllocatedFunds, uint256 availableFunds, uint256 sharePrice)
    {
        totalAssetsManaged = totalAssets();
        totalAllocatedFunds = totalAllocated;
        availableFunds = availableLiquidity();
        sharePrice = convertToAssets(10 ** decimals());
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {}

    function deposit(uint256 amount, address receiver) public virtual onlyProtocolLevel override returns (uint256 shares) {
        return super.deposit(amount, receiver);
    }
    function withdraw(uint256 assets, address receiver, address owner) public virtual onlyProtocolLevel override returns (uint256 shares) {
        return super.withdraw(assets, receiver, owner);
    }
    function redeem(uint256 shares, address receiver, address owner) public virtual onlyProtocolLevel override returns (uint256 assets) {
        return super.redeem(shares, receiver, owner);
    }

    function mint(uint256 shares, address receiver) public virtual onlyProtocolLevel override returns (uint256 assets) {
        return super.mint(shares, receiver);
    }
}
