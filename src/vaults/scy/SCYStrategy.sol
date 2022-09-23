// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYBase, IERC20, IERC20Metadata, SafeERC20 } from "./SCYBase.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { AuthU } from "../../common/AuthU.sol";
import { FeesU } from "../../common/FeesU.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { TreasuryU } from "../../common/TreasuryU.sol";
import { Bank } from "../../bank/Bank.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// import "hardhat/console.sol";

struct Strategy {
	bytes32 symbol;
	address addr;
	uint96 maxDust;
	uint256 strategyId; // this is strategy specific token if 1155
	address yieldToken;
	IERC20 underlying;
	uint128 maxTvl; // pack all params and balances
	uint128 balance; // strategy balance in underlying
	uint128 uBalance; // underlying balance
	uint128 yBalance; // yield token balance
}

abstract contract SCYStrategy {
	function _stratDeposit(uint256 amount) internal virtual returns (uint256);

	function _stratRedeem(address to, uint256 amount)
		internal
		virtual
		returns (uint256 amntOut, uint256 amntToTransfer);

	function _stratClosePosition() internal virtual returns (uint256);

	function _stratGetAndUpdateTvl() internal virtual returns (uint256);

	function _strategyTvl() internal view virtual returns (uint256);

	function _stratMaxTvl() internal view virtual returns (uint256);

	function _stratCollateralToUnderlying() internal view virtual returns (uint256);

	function _stratValidate() internal virtual;
}
