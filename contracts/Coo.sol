// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 *  $COO — Sir Reginald Coo III, Pigeon of Prosperity
 *
 *  Design rules (these are the things listing sites and honeypot scanners check):
 *    - Fixed supply. Minted once in the constructor. There is no mint() function. Ever.
 *    - Zero transfer tax. No fee logic exists in this file at all.
 *    - No blacklist, no pause, no "cooldown", no max-transaction limit.
 *    - No proxy, no upgradeability. What you verify is what runs, forever.
 *    - The ONLY owner power is an anti-sniper max-wallet cap that:
 *        (a) can never be set below MIN_MAX_WALLET (1% of supply),
 *        (b) can never be lowered once set — only raised or removed,
 *        (c) expires on its own at LIMITS_EXPIRY (24h after deploy) even if the
 *            owner disappears, gets bored, or loses their keys.
 *      After that the contract is a plain, immutable ERC-20.
 */
contract Coo is ERC20, ERC20Burnable, ERC20Permit, Ownable2Step {
    /// @notice Total supply, minted once at deployment: 1,000,000,000 COO.
    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    /// @notice The max-wallet cap can never be configured below 1% of supply.
    uint256 public constant MIN_MAX_WALLET = MAX_SUPPLY / 100;

    /// @notice Timestamp after which limits are unenforceable, no matter what.
    uint256 public immutable LIMITS_EXPIRY;

    /// @notice Current max wallet size. 0 means limits are permanently off.
    uint256 public maxWallet;

    /// @notice Addresses that ignore the cap (router, pair, treasury, LP adder).
    mapping(address account => bool exempt) public isLimitExempt;

    event MaxWalletUpdated(uint256 previousMaxWallet, uint256 newMaxWallet);
    event LimitsRemovedForever();
    event LimitExemptionSet(address indexed account, bool exempt);

    error MaxWalletExceeded(address to, uint256 balanceAfter, uint256 cap);
    error CapTooLow(uint256 requested, uint256 minimum);
    error CapCannotBeLowered(uint256 current, uint256 requested);
    error LimitsAlreadyRemoved();

    /**
     * @param treasury  Receives 100% of supply at deploy. Splits happen off-chain,
     *                  transparently, per the distribution in TOKENOMICS.md.
     * @param initialOwner  Holds the temporary limit controls. Renounce after launch.
     */
    constructor(address treasury, address initialOwner)
        ERC20("Sir Reginald Coo III", "COO")
        ERC20Permit("Sir Reginald Coo III")
        Ownable(initialOwner)
    {
        require(treasury != address(0), "COO: treasury is zero");
        // initialOwner == 0 is already rejected by Ownable with OwnableInvalidOwner.

        LIMITS_EXPIRY = block.timestamp + 24 hours;
        maxWallet = MAX_SUPPLY / 50; // 2% at launch

        isLimitExempt[treasury] = true;
        isLimitExempt[initialOwner] = true;
        isLimitExempt[address(0)] = true;
        isLimitExempt[address(this)] = true;

        _mint(treasury, MAX_SUPPLY);
    }

    /// @notice True while the anti-sniper cap is still being enforced.
    function limitsActive() public view returns (bool) {
        return maxWallet != 0 && block.timestamp < LIMITS_EXPIRY;
    }

    /// @notice Raise the cap. Cannot lower it, cannot go under 1% of supply.
    function setMaxWallet(uint256 newMaxWallet) external onlyOwner {
        uint256 current = maxWallet;
        if (current == 0) revert LimitsAlreadyRemoved();
        if (newMaxWallet < MIN_MAX_WALLET) revert CapTooLow(newMaxWallet, MIN_MAX_WALLET);
        if (newMaxWallet < current) revert CapCannotBeLowered(current, newMaxWallet);
        maxWallet = newMaxWallet;
        emit MaxWalletUpdated(current, newMaxWallet);
    }

    /// @notice Turn the cap off permanently. This is a one-way door.
    function removeLimits() external onlyOwner {
        if (maxWallet == 0) revert LimitsAlreadyRemoved();
        emit MaxWalletUpdated(maxWallet, 0);
        maxWallet = 0;
        emit LimitsRemovedForever();
    }

    /// @notice Exempt an address (pair, router, locker) from the cap.
    function setLimitExempt(address account, bool exempt) external onlyOwner {
        if (maxWallet == 0) revert LimitsAlreadyRemoved();
        isLimitExempt[account] = exempt;
        emit LimitExemptionSet(account, exempt);
    }

    /// @dev The single hook every transfer, mint and burn routes through.
    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);

        if (limitsActive() && !isLimitExempt[to]) {
            uint256 balanceAfter = balanceOf(to);
            if (balanceAfter > maxWallet) {
                revert MaxWalletExceeded(to, balanceAfter, maxWallet);
            }
        }
    }
}
