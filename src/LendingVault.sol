// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {IAccessRegistry} from "@qiro/interfaces/IAccessRegistry.sol";
import {CustomRevert} from "@qiro/libraries/CustomRevert.sol";
import {Roles} from "@qiro/helper/Roles.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {UUPSUpgradeable} from "@solady/utils/UUPSUpgradeable.sol";
import {LendingVaultStorage} from "@qiro/storage/LendingVault.sol";

/**
 * @title LendingVault
 * @dev ERC-4626 compliant vault for deposits and withdrawals
 * @notice This vault accepts deposits and allocates funds to borrow vaults
 */
contract LendingVault is LendingVaultStorage,Roles, ERC4626,UUPSUpgradeable{
    using CustomRevert for bytes4;
    using SafeTransferLib for address;

    constructor() {
        _disableInitializers();
    }

    function initializeLendingVault(TokenInfo memory _tokenInfo, address _accessRegistry) external initializer {
        if (_accessRegistry == address(0)) InvalidAddress.selector.revertWith();
        TokenInfo storage tokenInfo = tokenInfo();
        initializeRoles(_accessRegistry);
        tokenInfo.name = _tokenInfo.name;
        tokenInfo.symbol = _tokenInfo.symbol;
        tokenInfo.asset = _tokenInfo.asset;
    }

    function name() public view override returns (string memory) {
        return tokenInfo().name;
    }

    function symbol() public view override returns (string memory) {
        return tokenInfo().symbol;
    }

    function asset() public view override returns (address) {
        return tokenInfo().asset;
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

        LendingVaultInfo storage lendingVaultInfo = lendingVaultInfo();
        lendingVaultInfo.borrowVaultAllocations[msg.sender] += amount;
        lendingVaultInfo.totalAllocated += amount;

        asset().safeTransfer(msg.sender, amount);

        emit FundsAllocated(msg.sender, amount);
        return true;
    }

    /**
     * @dev Return funds from a borrow vault
     * @param principal Principal amount being returned
     * @param interest Interest amount being paid
     */
    function returnFunds(uint256 principal, uint256 interest) external onlyProtocolLevel {
        LendingVaultInfo storage lendingVaultInfo = lendingVaultInfo();
        if (principal > lendingVaultInfo.borrowVaultAllocations[msg.sender]) InvalidAmount.selector.revertWith();

        uint256 totalReturn = principal + interest;
        if (totalReturn == 0) InvalidAmount.selector.revertWith();

        // Update allocations
        lendingVaultInfo.borrowVaultAllocations[msg.sender] -= principal;
        lendingVaultInfo.totalAllocated -= principal;

        // Transfer funds back
        asset().safeTransferFrom(msg.sender, address(this), totalReturn);

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
        uint256 vaultBalance = asset().balanceOf(address(this));
        return vaultBalance; // All balance is available since allocated funds are transferred out
    }

    /**
     * @dev Total assets under management (including allocated funds)
     * @return Total assets
     */
    function totalAssets() public view virtual override returns (uint256) {
        return asset().balanceOf(address(this)) + lendingVaultInfo().totalAllocated;
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
        totalAllocatedFunds = lendingVaultInfo().totalAllocated;
        availableFunds = availableLiquidity();
        sharePrice = convertToAssets(10 ** decimals());
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {}

    function deposit(uint256 amount, address receiver)
        public
        virtual
        override
        onlyProtocolLevel
        returns (uint256 shares)
    {
        return super.deposit(amount, receiver);
    }

    function redeem(uint256 , address , address )
        public
        virtual
        override
        returns (uint256 )
    {
        NotSupported.selector.revertWith();
    }

    function mint(uint256 , address )
        public
        virtual
        override
        returns (uint256 )
    {
        NotSupported.selector.revertWith();
    }

    function withdraw(uint256 assets, address to, address owner)
        public
        virtual
        onlyProtocolLevel
        override
        returns (uint256 shares)
    {
        if (assets > maxWithdraw(owner)) InvalidAmount.selector.revertWith();
        shares = previewWithdraw(assets);
        _withdraw(to, to, owner, assets, shares);
    }
}
