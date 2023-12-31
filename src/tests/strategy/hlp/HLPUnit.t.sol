// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IUniswapV2Pair } from "interfaces/uniswap/IUniswapV2Pair.sol";
import { HarvestSwapParams } from "strategies/mixins/IFarmable.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeETH } from "libraries/SafeETH.sol";
import { IStrategy } from "interfaces/IStrategy.sol";
import { HLPSetup, SCYVault, HLPCore } from "./HLPSetup.sol";
import { UnitTestVault } from "../common/UnitTestVault.sol";
import { UnitTestStrategy } from "../common/UnitTestStrategy.sol";
import { SectorErrors } from "interfaces/SectorErrors.sol";
import { AggregatorVault } from "vaults/sectorVaults/AggregatorVault.sol";
import { WithdrawRecord } from "../../../common/BatchedWithdraw.sol";
import { INFTPool } from "strategies/modules/camelot/interfaces/INFTPool.sol";
import { CamelotFarm } from "strategies/modules/camelot/CamelotFarm.sol";

import "hardhat/console.sol";

contract HLPUnit is HLPSetup, UnitTestStrategy, UnitTestVault {
	/// INIT

	function testShouldInit() public override {
		assertEq(strategy.vault(), address(vault));
		assertEq(vault.getFloatingAmount(address(underlying)), 0);
		assertEq(strategy.decimals(), underlying.decimals());
	}

	/// ROLES?

	/// EMERGENCY WITHDRAW

	// function testEmergencyWithdraw() public {
	// 	uint256 amount = 1e18;
	// 	underlying.mint(address(strategy), amount);
	// 	SafeETH.safeTransferETH(address(strategy), amount);

	// 	address withdrawTo = address(222);

	// 	tokens.push(underlying);
	// 	strategy.emergencyWithdraw(withdrawTo, tokens);

	// 	assertEq(underlying.balanceOf(withdrawTo), amount);
	// 	assertEq(withdrawTo.balance, amount);

	// 	assertEq(underlying.balanceOf(address(strategy)), 0);
	// 	assertEq(address(strategy).balance, 0);
	// }

	// CONFIG

	function testDepositOverMaxTvl() public {
		uint256 amount = strat.getMaxDeposit() + 1;
		depositRevert(self, amount, SectorErrors.MaxTvlReached.selector);
	}

	function testSafeCollateralRatio() public {
		vm.expectRevert("STRAT: BAD_INPUT");
		strategy.setSafeCollateralRatio(900);

		vm.expectRevert("STRAT: BAD_INPUT");
		strategy.setSafeCollateralRatio(9000);

		strategy.setSafeCollateralRatio(7700);
		assertEq(strategy.safeCollateralRatio(), 7700);

		vm.prank(guardian);
		vm.expectRevert("ONLY_OWNER");
		strategy.setSafeCollateralRatio(7700);

		vm.prank(manager);
		vm.expectRevert("ONLY_OWNER");
		strategy.setSafeCollateralRatio(7700);
	}

	function testMinLoanHealth() public {
		vm.expectRevert("STRAT: BAD_INPUT");
		strategy.setMinLoanHeath(0.9e18);

		strategy.setMinLoanHeath(1.29e18);
		assertEq(strategy.minLoanHealth(), 1.29e18);

		vm.prank(guardian);
		vm.expectRevert("ONLY_OWNER");
		strategy.setMinLoanHeath(1.29e18);

		vm.prank(manager);
		vm.expectRevert("ONLY_OWNER");
		strategy.setMinLoanHeath(1.29e18);
	}

	function testSetMaxPriceMismatch() public {
		strategy.setMaxDefaultPriceMismatch(1e18);
	}

	function testMaxDefaultPriceMismatch() public {
		vm.expectRevert("STRAT: BAD_INPUT");
		strategy.setMaxDefaultPriceMismatch(24);

		uint256 bigMismatch = 2 + strategy.maxAllowedMismatch();
		vm.prank(guardian);
		vm.expectRevert("STRAT: BAD_INPUT");
		strategy.setMaxDefaultPriceMismatch(bigMismatch);

		vm.prank(guardian);
		strategy.setMaxDefaultPriceMismatch(120);
		assertEq(strategy.maxDefaultPriceMismatch(), 120);

		vm.prank(manager);
		vm.expectRevert(_accessErrorString(GUARDIAN, manager));
		strategy.setMaxDefaultPriceMismatch(120);
	}

	/*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

	function testRebalanceLendFuzz(uint256 fuzz) public {
		uint256 priceAdjust = bound(fuzz, 1.1e18, 2e18);
		skip(1);
		deposit(self, dec);
		skip(1);

		uint256 rebThresh = strategy.rebalanceThreshold();

		adjustPrice(priceAdjust);

		uint256 minLoanHealth = strategy.minLoanHealth();
		if (strategy.loanHealth() <= minLoanHealth) {
			assertGt(strategy.getPositionOffset(), rebThresh);
			strategy.rebalanceLoan();
			assertGt(strategy.loanHealth(), minLoanHealth);
		}
		skip(1);

		// skip if we don't need to rebalance
		if (strategy.getPositionOffset() <= rebThresh) return;
		strategy.rebalance(priceSlippageParam());
		assertApproxEqAbs(strategy.getPositionOffset(), 0, 11);
		skip(1);

		// put price back
		adjustPrice(1e36 / priceAdjust);

		if (strategy.getPositionOffset() <= rebThresh) return;
		strategy.rebalance(priceSlippageParam());
		// strategy.logTvl();

		assertApproxEqAbs(strategy.getPositionOffset(), 0, 11);
	}

	// TODO ?
	// function testRebalanceAfterLiquidation() public {
	// 	deposit(self, dec);

	// 	// liquidates borrows and 1/2 of collateral
	// 	strategy.liquidate();

	// 	strategy.rebalance(priceSlippageParam());
	// 	assertApproxEqAbs(strategy.getPositionOffset(), 0, 11);
	// }

	function testPriceOffsetEdge() public {
		deposit(self, dec);

		adjustPrice(1.08e18);

		uint256 health = strategy.loanHealth();
		uint256 positionOffset = strategy.getPositionOffset();

		adjustOraclePrice(1.10e18);

		health = strategy.loanHealth();
		positionOffset = strategy.getPositionOffset();

		assertLt(health, strategy.minLoanHealth());

		strategy.rebalanceLoan();
		assertLt(positionOffset, strategy.rebalanceThreshold());

		strategy.rebalance(priceSlippageParam());

		health = strategy.loanHealth();
		positionOffset = strategy.getPositionOffset();
		// assertGt(health, strategy.minLoanHealth());
		assertLt(positionOffset, 10);
	}

	function testPriceOffsetEdge2() public {
		deposit(self, dec);

		adjustPrice(0.92e18);

		uint256 health = strategy.loanHealth();
		uint256 positionOffset = strategy.getPositionOffset();

		adjustOraclePrice(0.9e18);

		health = strategy.loanHealth();
		positionOffset = strategy.getPositionOffset();

		assertGt(positionOffset, strategy.rebalanceThreshold());
		strategy.rebalance(priceSlippageParam());

		health = strategy.loanHealth();
		positionOffset = strategy.getPositionOffset();
		assertGt(health, strategy.minLoanHealth());
		assertLt(positionOffset, 10);
	}

	function testMaxPriceOffset() public {
		deposit(self, dec);

		moveUniswapPrice(address(uniPair), address(underlying), short, 0.7e18);

		uint256 offset = priceSlippageParam();
		vm.prank(manager);
		vm.expectRevert("HLP: MAX_MISMATCH");
		strategy.rebalance(offset);

		vm.prank(manager);
		vm.expectRevert("HLP: PRICE_MISMATCH");
		strategy.rebalanceLoan();

		vm.prank(guardian);
		vault.closePosition(0, offset);
	}

	function testRebalanceSlippage() public {
		deposit(self, dec);

		// this creates a price offset
		moveUniswapPrice(address(uniPair), address(underlying), short, 0.7e18);

		vm.prank(address(1));
		vm.expectRevert("HLP: PRICE_MISMATCH");
		strategy.rebalanceLoan();

		vm.expectRevert("HLP: PRICE_MISMATCH");
		strategy.rebalance(0);

		vm.expectRevert("HLP: PRICE_MISMATCH");
		vault.closePosition(0, 0);

		vm.expectRevert("HLP: PRICE_MISMATCH");
		strategy.removeLiquidity(1000, 0);
	}

	/*///////////////////////////////////////////////////////////////
	                    HEDGEDLP TESTS
	//////////////////////////////////////////////////////////////*/

	function testWithdrawFromFarm() public {
		deposit(dec);
		assertEq(uniPair.balanceOf(address(strategy)), 0);
		vm.expectRevert(IStrategy.NotPaused.selector);
		strategy.withdrawFromFarm();
		vault.setMaxTvl(0);
		strategy.withdrawFromFarm();
		assertGt(uniPair.balanceOf(address(strategy)), 0);
	}

	function testWithdrawLiquidity() public {
		deposit(dec);
		vm.expectRevert(IStrategy.NotPaused.selector);
		strategy.removeLiquidity(0, 0);
		vault.setMaxTvl(0);
		strategy.withdrawFromFarm();
		uint256 lp = uniPair.balanceOf(address(strategy));
		strategy.removeLiquidity(lp, 0);
		assertEq(uniPair.balanceOf(address(strategy)), 0);
	}

	function testRedeemCollateral() public {
		deposit(dec);
		(, uint256 collateralBalance, uint256 shortPosition, , , ) = strategy.getTVL();
		deal(short, address(strategy), shortPosition / 10);
		vm.expectRevert(IStrategy.NotPaused.selector);
		strategy.redeemCollateral(shortPosition / 10, collateralBalance / 10);
		vault.setMaxTvl(0);
		strategy.redeemCollateral(shortPosition / 10, collateralBalance / 10);
		(, uint256 newCollateralBalance, uint256 newShortPosition, , , ) = strategy.getTVL();
		assertApproxEqRel(
			newCollateralBalance,
			collateralBalance - collateralBalance / 10,
			.0001e18
		);
		assertApproxEqRel(newShortPosition, shortPosition - shortPosition / 10, .0001e18);
	}

	// slippage in basis points
	function priceSlippageParam() public view override returns (uint256 priceOffset) {
		return strategy.getPriceOffset();
	}

	function testClosePositionEdge() public {
		skip(1);
		address short = address(strategy.short());
		uint256 amount = 1000e6;

		deal(address(underlying), user2, amount);
		vm.startPrank(user2);
		underlying.approve(address(vault), amount);
		vault.deposit(user2, address(underlying), amount, amount);
		vm.stopPrank();

		skip(1);
		harvest();
		skip(1);

		deal(short, address(strategy), 14368479712190599);
		vault.closePosition(0, strategy.getPriceOffset());
	}

	function testRebalanceEdgeCase() public {
		uint256 amnt = getAmnt();
		deposit(self, amnt);
		deal(address(short), address(strategy), 10e18);

		uint256 pOffset = strategy.getPositionOffset();
		assertGt(pOffset, 400);
		rebalance();
	}

	function testPerformUpkeep() public {
		uint256 amnt = getAmnt();
		deposit(self, amnt);
		bytes memory checkData;
		(bool performUpkeep, bytes memory performData) = strategy.checkUpkeep(checkData);
		assertEq(performUpkeep, false);
		assertEq(performData.length, 0);

		adjustPrice(1.1e18);
		// test small oracle offset of 2% to ensure manager can call rebalance
		adjustOraclePrice(1.02e18);

		(performUpkeep, performData) = strategy.checkUpkeep(checkData);
		assertEq(performUpkeep, true);
		uint8 action = abi.decode(performData, (uint8));
		assertEq(action, strategy.REBALANCE());
		assertEq(performUpkeep, true);

		vm.prank(user1);
		vm.expectRevert("HLP: PRICE_MISMATCH");
		strategy.performUpkeep(performData);

		vm.prank(manager);
		strategy.performUpkeep(performData);
		assertEq(strategy.getPositionOffset(), 0);

		adjustOraclePrice(1.1e18);
		(performUpkeep, performData) = strategy.checkUpkeep(checkData);
		assertEq(performUpkeep, true);
		action = abi.decode(performData, (uint8));
		assertEq(action, strategy.REBALANCE_LOAN());

		skip(1);
		vm.prank(user1);
		vm.expectRevert("HLP: PRICE_MISMATCH");
		strategy.performUpkeep(performData);

		vm.prank(manager);
		strategy.performUpkeep(performData);
		assertGt(strategy.loanHealth(), 1.25e18);
		vm.stopPrank();
	}

	function testRebalancePublic() public {
		adjustOraclePrice(1.014e18);
		vm.startPrank(user1);
		uint256 priceOffset = strategy.getPriceOffset();
		vm.expectRevert("HLP: PRICE_MISMATCH");
		strategy.rebalance(priceOffset);

		vm.expectRevert("HLP: PRICE_MISMATCH");
		strategy.rebalanceLoan();
		vm.stopPrank();
	}

	// function testDeployedDeposit() public {
	// 	address dVaultAddr = 0xcE94D3C4660dEF1Be6C2D79Ff7c0006cB1f6B324;
	// 	SCYVault dvault = SCYVault(payable(dVaultAddr));

	// 	address acc = 0x157875C30F83729Ce9c1E7A1568ec00250237862;
	// 	uint256 amount = 2000e6 / 4;
	// 	uint256 minSharesOut = dvault.underlyingToShares(amount);

	// 	address stratAddr = address(dvault.strategy());

	// 	bytes memory code = address(strategy).code;
	// 	address targetAddr = stratAddr;
	// 	vm.etch(targetAddr, code);

	// 	HLPCore _strategy = HLPCore(payable(stratAddr));

	// 	uint256 depAmnt = dvault.getDepositAmnt(amount);
	// 	console.log(minSharesOut, depAmnt, (10000 * (minSharesOut - depAmnt)) / minSharesOut);

	// 	console.log("positionOffset", _strategy.getPositionOffset());
	// 	logTvl(IStrategy(address(_strategy)));

	// 	vm.startPrank(acc);
	// 	underlying.approve(address(dvault), amount);
	// 	dvault.deposit(acc, address(underlying), amount, (minSharesOut * 9930) / 10000);

	// 	vm.stopPrank();
	// }

	// function testDeployedRebalance() public {
	// 	SCYVault dvault = SCYVault(payable(0x7acE71f029fe98E2ABdb49aA5a9f86D916088e7A));
	// 	HLPCore _strategy = HLPCore(payable(address(dvault.strategy())));

	// 	logTvl(IStrategy(address(_strategy)));
	// 	console.log("short balance", _strategy.short().balanceOf(address(_strategy)));
	// 	uint256 priceOffset = _strategy.getPriceOffset();
	// 	vm.prank(0x8aB0800dc1c5dbC0fdaF12D660f1846baf635050);
	// 	_strategy.rebalance(priceOffset);
	// 	assertApproxEqAbs(_strategy.getPositionOffset(), 0, 2, "position offset after rebalance");
	// 	skip(1);
	// }

	// function testDeployedHarvest() public {
	// 	SCYVault dvault = SCYVault(payable(0x7c3f91a0806beF783686Bdf4968BD90e79732F79));
	// 	HLPCore _strategy = HLPCore(payable(address(dvault.strategy())));
	// 	// vm.prank(0x6DdF9DA4C37DF97CB2458F85050E09994Cbb9C2A);
	// 	// strategy.rebalance(0);
	// 	// vm.warp(block.timestamp + 1 * 60 * 60 * 24);

	// 	harvestParams.min = 0;
	// 	harvestParams.deadline = block.timestamp + 1;

	// 	harvestLendParams.min = 0;
	// 	harvestLendParams.deadline = block.timestamp + 1;

	// 	// _strategy.getAndUpdateTvl();
	// 	uint256 tvl = _strategy.getTotalTVL();

	// 	HarvestSwapParams[] memory farmParams = new HarvestSwapParams[](1);
	// 	farmParams[0] = harvestParams;

	// 	HarvestSwapParams[] memory lendParams = new HarvestSwapParams[](1);
	// 	lendParams[0] = harvestLendParams;

	// 	uint256 vaultTvl = dvault.getTvl();

	// 	vm.prank(0x8aB0800dc1c5dbC0fdaF12D660f1846baf635050);
	// 	(uint256[] memory harvestAmnts, uint256[] memory harvestLendAmnts) = dvault.harvest(
	// 		vaultTvl,
	// 		vaultTvl / 10,
	// 		farmParams,
	// 		lendParams
	// 	);

	// 	uint256 newTvl = _strategy.getTotalTVL();
	// 	assertGt(harvestAmnts[0], 0);
	// 	assertGt(harvestLendAmnts[0], 0);
	// 	assertGt(newTvl, tvl);
	// }

	// function testDepWithdraw() public {
	// 	AggregatorVault dVault = AggregatorVault(
	// 		payable(0xbe2Be6a2DAcf9dCC76903756ee8e085B1C5a2c30)
	// 	);

	// 	address acc = 0x4643731FA0406F21A6cC479E442BB4e59b742C69;
	// 	WithdrawRecord memory w = dVault.getWithdrawStatus(acc);
	// 	uint256 redeem = dVault.convertToAssets(dVault.pendingRedeem());

	// 	console.log("shares value", w.shares, w.value);
	// 	console.log("float, redeem", dVault.getFloat(), dVault.floatAmnt(), redeem);

	// 	vm.prank(acc);
	// 	dVault.redeem(acc);
	// }
}
