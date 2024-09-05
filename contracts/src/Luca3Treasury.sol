// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IProxy.sol";
import "./Luca3Auth.sol";

/// @title Luca3Treasury
/// @author Yudhishthra Sugumaran @ Luca3
/// @notice This contract manages the treasury for the Luca3 system, allowing ETH to USDC swaps for token-bound accounts
/// @dev Inherits from ReentrancyGuard to prevent reentrancy attacks
contract Luca3Treasury is ReentrancyGuard {
    /// @notice The USDC token contract
    IERC20 public usdcToken;

    /// @notice The address of the ETH/USD price proxy contract
    address constant ETH_USD_PRICE_PROXY =
        0xB7ce7B052836c69EaB40a1D5C0b2baeE8eFB86C7;

    /// @notice The address of the USDC/USD price proxy contract
    address constant USDC_USD_PRICE_PROXY =
        0x5fb6E1fBCB474E1aAfFb7C2104d731633D8c3D63;

    /// @notice The Luca3Auth contract instance
    Luca3Auth public luca3Auth;

    /// @notice Emitted when a swap from ETH to USDC occurs
    /// @param tba The address of the token-bound account that performed the swap
    /// @param ethAmount The amount of ETH swapped
    /// @param usdcAmount The amount of USDC received
    event Swapped(address indexed tba, uint256 ethAmount, uint256 usdcAmount);

    //Custom errors
    error InsufficientUSDCInTreasury();
    error MustSendETH();
    error OnlyTBA();
    error OnlyAdmin();
    error USDCTransferFailed();

    /// @notice Constructor to initialize the contract
    /// @param _usdcToken The address of the USDC token contract
    constructor(address _usdcToken) {
        usdcToken = IERC20(_usdcToken);
    }

    /// @notice Swaps ETH for USDC
    /// @dev Only token-bound accounts can perform this swap
    /// @param cardUID The unique identifier of the card associated with the token-bound account
    function swapEthForUsdc(
        string memory cardUID
    ) external payable nonReentrant {
        if (msg.value == 0) revert MustSendETH();
        if (!luca3Auth.isTBA(cardUID, msg.sender)) revert OnlyTBA();

        (int224 ethUsdPrice, ) = IProxy(ETH_USD_PRICE_PROXY).read();
        (int224 usdcUsdPrice, ) = IProxy(USDC_USD_PRICE_PROXY).read();

        uint256 usdAmount = (msg.value * uint224(ethUsdPrice)) / 1e18;
        uint256 usdcAmount = (usdAmount * 1e6) / uint224(usdcUsdPrice);

        if (usdcToken.balanceOf(address(this)) < usdcAmount)
            revert InsufficientUSDCInTreasury();

        bool success = usdcToken.transfer(msg.sender, usdcAmount);
        if (!success) revert USDCTransferFailed();

        emit Swapped(msg.sender, msg.value, usdcAmount);
    }

    /// @notice Withdraws USDC from the treasury
    /// @dev Only the admin of Luca3Auth can withdraw
    /// @param amount The amount of USDC to withdraw
    function withdrawUsdc(uint256 amount) external {
        if (msg.sender != luca3Auth.admin_()) revert OnlyAdmin();
        if (usdcToken.balanceOf(address(this)) < amount)
            revert InsufficientUSDCInTreasury();

        bool success = usdcToken.transfer(msg.sender, amount);
        require(success, "USDC transfer failed");
    }

    /// @notice Allows the contract to receive ETH
    receive() external payable {}

    //Function to update Luca3Auth address
    function updateLuca3Auth(address _luca3Auth) external {
        luca3Auth = Luca3Auth(_luca3Auth);
    }
}
