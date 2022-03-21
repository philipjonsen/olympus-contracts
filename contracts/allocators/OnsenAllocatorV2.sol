// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.10;
import "../libraries/Address.sol";

///  ========== TYPES ==========
import "../types/BaseAllocator.sol";

///  ========== INTERFACES ==========
import "../interfaces/IMasterChef.sol";
import "../interfaces/ISushiBar.sol";

/**
 *  @notice Contract deploys liquidity from treasury into the Onsen program,
 *  earning $SUSHI that can be staked and/or deposited into the treasury.
 */
contract OnsenAllocatorV2 is BaseAllocator {
    using SafeERC20 for IERC20;

    /// ========== STATE VARIABLES ==========

    address public sushi; // $SUSHI token
    address public xSushi; // $xSUSHI token
    address public masterChef; // Onsen contract

    address public treasury; // Olympus Treasury

    /// ========== CONSTRUCTOR ==========

    constructor(
        address _chef,
        address _sushi,
        address _xSushi,
        address _treasury,
        AllocatorInitData memory data
    ) BaseAllocator(data) {
        require(_chef != address(0));
        masterChef = _chef;
        require(_sushi != address(0));
        sushi = _sushi;
        require(_xSushi != address(0));
        xSushi = _xSushi;
        require(_treasury != address(0));
        treasury = _treasury;

        /**  @dev approve for safety, sushi is being staked and xsushi is being instantly sent to treasury and that is fine
         *   but to be absolutely safe this one approve won't hurt
         */
        IERC20(sushi).approve(address(extender), type(uint256).max);
        IERC20(xSushi).approve(address(extender), type(uint256).max);
    }

    /**
     * @notice Figure out which LP tokens to be deposited into onsen, then deposit it into onsen pool and stake the sushi tokens that are returned.
     * 1- Deposit LP token into onsen, if deposit is succesfull we should get in return sushi tokens
     * 2- Stake the Sushi rewards tokens returned from deposit LP tokens and as rewards form onsen LP stake, we should get in return xSushi tokens
     * 3- Return the xSushi tokens to treasury
     * 4- Calculate gains/loss
     */
    function _update(uint256 id) internal override returns (uint128 gain, uint128 loss) {
        uint256 index = tokenIds[id];
        IERC20 LPtoken = _tokens[index];
        uint256 balance = LPtoken.balanceOf(address(this));

        /// Deposit LP token into onsen, if deposit succesfull this address should have in return sushi tokens
        if (balance > 0) {
            LPtoken.approve(masterChef, balance);
            IMasterChef(masterChef).deposit(id, balance);
        }

        /// Stake the sushi tokens
        _stakeSushi();

        ///Calculate gains/loss
        /// Retrieve current balance for pool and address
        UserInfo memory currentUserInfo = IMasterChef(masterChef).userInfo(id, address(this));

        uint256 last = extender.getAllocatorAllocated(id) + extender.getAllocatorPerformance(id).gain;

        if (currentUserInfo.amount >= last) {
            gain = uint128(currentUserInfo.amount - last);
        } else {
            loss = uint128(last - currentUserInfo.amount);
        }
    }

    /** @notice Asuming the index of the amounts [] can be use as parameter for the mapping tokenIds
     *   Example:
     *   amounts => [20,50,150]
     *   So the values that will be used to retrieve the id used in onsen will be 0, 1 , 2
     */
    function deallocate(uint256[] memory amounts) public override onlyGuardian {
        for (uint256 i; i < amounts.length; i++) {
            uint256 amount = amounts[i];
            if (amount > 0) {
                IMasterChef(masterChef).withdraw(tokenIds[i], amount); // withdraw from Onsen
            }
        }
    }

    function _deactivate(bool panic) internal override {}

    function _prepareMigration() internal override {}

    function amountAllocated(uint256 id) public view override returns (uint256) {
        UserInfo memory currentUserInfo = IMasterChef(masterChef).userInfo(id, address(this));
        return currentUserInfo.amount;
    }

    function rewardTokens() public view override returns (IERC20[] memory) {
        IERC20[] memory rewards = new IERC20[](1);
        rewards[0] = IERC20(sushi);
        return rewards;
    }

    function utilityTokens() public view override returns (IERC20[] memory) {
        IERC20[] memory utility = new IERC20[](2);
        utility[0] = IERC20(sushi);
        utility[1] = IERC20(xSushi);
        return utility;
    }

    function name() external pure override returns (string memory) {
        return "OnsenAllocator";
    }

    function setTreasury(address treasuryAddress) external onlyGuardian {
        treasury = treasuryAddress;
    }

    function setSushi(address sushiAddress) external onlyGuardian {
        sushi = sushiAddress;
    }

    function setXSushi(address xSushiAddress) external onlyGuardian {
        xSushi = xSushiAddress;
    }

    function setMasterChefAddress(address masterChefAddress) external onlyGuardian {
        masterChef = masterChefAddress;
    }

    /// ========== INTERNAL FUNCTIONS ==========

    /**
     * @notice stake sushi rewards
     */
    function _stakeSushi() internal {
        uint256 balance = IERC20(sushi).balanceOf(address(this));
        if (balance > 0) {
            IERC20(sushi).approve(xSushi, balance);
            ISushiBar(xSushi).enter(balance); // stake sushi

            uint256 xBalance = IERC20(xSushi).balanceOf(address(this));
            IERC20(xSushi).safeTransfer(treasury, xBalance); // transfer xSushi to treasury
        }
    }

    /**
     *  @notice pending $SUSHI rewards
     *  @return uint
     */
    function _pendingSushi(uint256 pid) internal view returns (uint256) {
        return IMasterChef(masterChef).pendingSushi(pid, address(this));
    }
}
