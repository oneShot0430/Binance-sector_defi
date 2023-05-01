// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IStrategy } from "interfaces/IStrategy.sol";
import { HLPSetup, SCYVault, HLPCore } from "./HLPSetup.sol";
import { CamelotFarm, IXGrailToken, INFTPool } from "strategies/modules/camelot/CamelotFarm.sol";
import { CamelotSectGrailFarm, ISectGrail } from "strategies/modules/camelot/CamelotSectGrailFarm.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "hardhat/console.sol";

contract CamelotFarmTest is HLPSetup {
	function getStrategy() public pure override returns (string memory) {
		return "HLP_USDC-ETH_Camelot_arbitrum";
	}

	CamelotSectGrailFarm cFarm;
	INFTPool farm;
	ISectGrail sectGrail;
	IXGrailToken xGrailToken;

	function setupHook() public override {
		cFarm = CamelotSectGrailFarm(address(strategy));
		farm = INFTPool(cFarm.farm());
		sectGrail = cFarm.sectGrail();
		xGrailToken = sectGrail.xGrailToken();
	}

	function testCamelotFarm() public {
		if (!compare(contractType, "CamelotAave")) return;
		uint256 amnt = getAmnt();
		deposit(self, amnt);
		harvest();

		uint256 positionId = cFarm.positionId();

		address yieldBooster = farm.yieldBooster();
		uint256 xGrailAllocation = xGrailToken.usageAllocations(address(sectGrail), yieldBooster);
		assertGt(xGrailAllocation, 0, "xGrailAllocation should be greater than 0");

		(
			uint256 amount,
			uint256 amountWithMultiplier,
			uint256 startLockTime,
			uint256 lockDuration,
			uint256 lockMultiplier,
			uint256 rewardDebt,
			uint256 boostPoints,
			uint256 totalMultiplier
		) = farm.getStakingPosition(positionId);

		assertGt(amount, 0, "amount should be gt 0");
		assertGt(boostPoints, 0, "boostPoints should be greater than 0");
		uint256 xGrailBal = xGrailToken.balanceOf(address(sectGrail));
		assertEq(xGrailBal, 0, "xGrailBal should be 0");

		skip(1);
		vault.closePosition(0, 0);
		xGrailAllocation = xGrailToken.usageAllocations(address(sectGrail), yieldBooster);
		assertEq(xGrailAllocation, 0, "xGrailAllocation should be 0");

		xGrailBal = xGrailToken.balanceOf(address(sectGrail));
		assertGt(xGrailBal, 0, "xGrailBal should be greater than 0");
	}

	function testCamelotDealocate() public {
		if (!compare(contractType, "CamelotAave")) return;
		uint256 amnt = getAmnt();
		deposit(self, amnt);
		harvest();
		uint256 allocated = sectGrail.getAllocations(address(strategy));
		cFarm.deallocateSectGrail(allocated);
		allocated = sectGrail.getAllocations(address(strategy));
		assertEq(allocated, 0, "allocated should be 0");
	}

	function testCamelotTransferSectGrail() public {
		if (!compare(contractType, "CamelotAave")) return;
		uint256 amnt = getAmnt();
		deposit(self, amnt);
		harvest();
		uint256 allocated = sectGrail.getAllocations(address(strategy));
		cFarm.deallocateSectGrail(allocated);
		uint256 balance = IERC20(address(sectGrail)).balanceOf(address(strategy));
		cFarm.transferSectGrail(self, balance);
		allocated = sectGrail.getAllocations(address(strategy));
		assertEq(allocated, 0, "allocated should be 0");
	}
}
