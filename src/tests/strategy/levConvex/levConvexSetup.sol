// SPDX_License_Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "interfaces/uniswap/ISimpleUniswapOracle.sol";
import { PriceUtils, UniUtils, IUniswapV2Pair } from "../../utils/PriceUtils.sol";

import { HarvestSwapParams } from "interfaces/Structs.sol";
import { levConvex } from "strategies/gearbox/levConvex.sol";
import { levConvex3Crv } from "strategies/gearbox/levConvex3Crv.sol";

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SCYStratUtils } from "../common/SCYStratUtils.sol";
import { IDegenNFT } from "interfaces/gearbox/IDegenNFT.sol";
import { ICreditFacade } from "interfaces/gearbox/ICreditFacade.sol";
import { LevConvexConfig } from "strategies/gearbox/ILevConvex.sol";

import { SCYWEpochVault, AuthConfig, FeeConfig } from "vaults/ERC5115/SCYWEpochVault.sol";
import { SCYVaultConfig } from "interfaces/ERC5115/ISCYVault.sol";

import "forge-std/StdJson.sol";

import "hardhat/console.sol";

contract levConvexSetup is SCYStratUtils {
	using UniUtils for IUniswapV2Pair;
	using stdJson for string;

	string TEST_STRATEGY = "LCVX_USDC-sUSD_Gearbox_mainnet"; // year fees/slippage 3.19%
	// string TEST_STRATEGY = "LCVX_USDC-FRAX_Gearbox_mainnet"; // year fees/slippage 4.28%

	// 3pool strats
	// string TEST_STRATEGY = "LCVX_USDC-gUSD-3Crv_Gearbox_mainnet"; // year fees/slippage 4.10%
	// string TEST_STRATEGY = "LCVX_USDC-FRAX-3Crv_Gearbox_mainnet"; // year fees/slippage 4.49%
	// string TEST_STRATEGY = "LCVX_USDC-lUSD-3Crv_Gearbox_mainnet"; // year fees/slippage 1.33%

	uint256 currentFork;

	levConvex strategy;

	SCYVaultConfig vaultConfig;

	bytes[] harvestPaths;
	bool is3crv;

	struct ConfigJSON {
		address a1_curveAdapter;
		address a2_curveAdapterDeposit;
		bool a3_acceptsNativeToken;
		address b_convexRewardPool;
		address c_creditFacade;
		address d_convexBooster;
		uint16 e1_coinId; // curve token index
		uint16 e2_riskId; // curve token index
		address f1_underlying;
		address f2_riskAsset;
		uint256 f3_riskAssetDecimals;
		uint16 g_leverageFactor;
		address h_farmRouter;
		address[] i_farmTokens;
		bytes[] j_harvestPaths;
		bool k_is3crv;
		string x_chain;
	}

	// TODO we can return a full array for a given chain
	// and test all strats...
	function getConfig(string memory symbol) public returns (LevConvexConfig memory _config) {
		string memory root = vm.projectRoot();
		string memory path = string.concat(root, "/ts/config/strategies.json");
		string memory json = vm.readFile(path);
		// bytes memory names = json.parseRaw(".strats");
		// string[] memory strats = abi.decode(names, (string[]));
		bytes memory strat = json.parseRaw(string.concat(".", symbol));
		ConfigJSON memory stratJson = abi.decode(strat, (ConfigJSON));

		_config.curveAdapter = stratJson.a1_curveAdapter;
		_config.curveAdapterDeposit = stratJson.a2_curveAdapterDeposit;
		_config.convexRewardPool = stratJson.b_convexRewardPool;
		_config.creditFacade = stratJson.c_creditFacade;
		_config.convexBooster = stratJson.d_convexBooster;
		_config.coinId = stratJson.e1_coinId;
		_config.underlying = stratJson.f1_underlying;
		_config.leverageFactor = stratJson.g_leverageFactor;
		_config.farmRouter = stratJson.h_farmRouter;

		is3crv = stratJson.k_is3crv;
		harvestPaths = stratJson.j_harvestPaths;
		vaultConfig.acceptsNativeToken = stratJson.a3_acceptsNativeToken;

		string memory RPC_URL = vm.envString(string.concat(stratJson.x_chain, "_RPC_URL"));
		uint256 BLOCK = vm.envUint(string.concat(stratJson.x_chain, "_BLOCK"));

		currentFork = vm.createFork(RPC_URL, BLOCK);
		vm.selectFork(currentFork);
	}

	function setUp() public {
		// TODO use JSON

		LevConvexConfig memory config = getConfig(TEST_STRATEGY);
		underlying = IERC20(config.underlying);

		/// todo should be able to do this via address and mixin
		vaultConfig.symbol = "TST";
		vaultConfig.name = "TEST";
		vaultConfig.yieldToken = config.convexRewardPool;
		vaultConfig.underlying = underlying;

		uint256 maxTvl = 1000000e6;
		vaultConfig.maxTvl = uint128(maxTvl);

		AuthConfig memory authConfig = AuthConfig({
			owner: owner,
			manager: manager,
			guardian: guardian
		});

		vault = deploySCYWEpochVault(authConfig, FeeConfig(treasury, .1e18, 0), vaultConfig);

		mLp = vault.MIN_LIQUIDITY();

		console.log("IS 3CRV", is3crv);

		strategy = is3crv
			? levConvex(address(new levConvex3Crv(authConfig, config)))
			: new levConvex(authConfig, config);

		vault.initStrategy(address(strategy));
		strategy.setVault(address(vault));

		underlying.approve(address(vault), type(uint256).max);

		configureUtils(address(underlying), address(strategy));

		/// mint dege nft to strategy
		ICreditFacade creditFacade = strategy.creditFacade();

		IDegenNFT degenNFT = IDegenNFT(creditFacade.degenNFT());
		address minter = degenNFT.minter();

		vm.prank(minter);
		degenNFT.mint(address(strategy), 200);

		// so close account doesn't create issues
		vm.roll(1);
		redeemSlippage = .001e18;
		// deposit(mLp);
	}

	function noRebalance() public override {}

	function adjustPrice(uint256 fraction) public override {}

	function harvest() public override {
		vm.warp(block.timestamp + 1 * 60 * 60 * 24);

		uint256 l = harvestPaths.length;

		HarvestSwapParams[] memory params1 = getHarvestParams();
		HarvestSwapParams[] memory params2 = new HarvestSwapParams[](0);

		strategy.getAndUpdateTvl();
		uint256 tvl = vault.getTvl();
		uint256 vaultTvl = vault.getTvl();
		(uint256[] memory harvestAmnts, ) = vault.harvest(
			vaultTvl,
			vaultTvl / 100,
			params1,
			params2
		);
		uint256 newTvl = vault.getTvl();

		assert(harvestAmnts.length == l);
		for (uint256 i; i < l; ++i) {
			if (harvestAmnts[i] == 0) {
				console.log("missing rewards for", i);
				console.logBytes(harvestPaths[i]);
				if (i > 1) continue;
			}
			assertGt(harvestAmnts[i], 0);
		}
		assertGt(newTvl, tvl, "tvl should increase");

		// assertEq(underlying.balanceOf(strategy.credAcc()), 0);
	}

	function getHarvestParams() public view returns (HarvestSwapParams[] memory) {
		uint256 l = harvestPaths.length;
		HarvestSwapParams[] memory params = new HarvestSwapParams[](l);

		for (uint256 i; i < l; ++i) {
			params[i].min = 0;
			params[i].deadline = block.timestamp + 1;
			params[i].pathData = harvestPaths[i];
		}

		return params;
	}

	function rebalance() public override {}

	// slippage in basis points
	function getSlippageParams(uint256 slippage)
		public
		view
		returns (uint256 expectedPrice, uint256 maxDelta)
	{
		// expectedPrice = strategy.getExpectedPrice();
		// maxDelta = (expectedPrice * slippage) / BASIS;
	}

	function adjustOraclePrice(uint256 fraction) public {}

	function getAmnt() public view virtual override returns (uint256) {
		/// needs to be over Gearbox deposit min
		return 50000e6;
	}

	function deposit(address user, uint256 amount) public virtual override {
		uint256 startTvl = vault.getAndUpdateTvl();
		uint256 startAccBalance = vault.underlyingBalance(user);
		deal(address(underlying), user, amount);
		uint256 minSharesOut = (vault.underlyingToShares(amount) * 9950) / 10000;

		uint256 startShares = IERC20(address(vault)).balanceOf(user);

		vm.startPrank(user);
		underlying.approve(address(vault), amount);
		vault.deposit(user, address(underlying), amount, minSharesOut);
		vm.stopPrank();

		uint256 stratTvl = strategy.getTvl();
		if (stratTvl == 0) {
			vm.prank(manager);
			vault.depositIntoStrategy(vault.uBalance(), minSharesOut);
		}

		uint256 tvl = vault.getAndUpdateTvl();
		uint256 endAccBalance = vault.underlyingBalance(user);

		assertApproxEqRel(
			IERC20(address(vault)).balanceOf(user) - startShares,
			minSharesOut,
			.01e18,
			"min estimate should be close"
		);

		// TODO this implies a 1.4% slippage / deposit fee
		assertApproxEqRel(tvl, startTvl + amount, .015e18, "tvl should update");
		assertApproxEqRel(
			tvl - startTvl,
			endAccBalance - startAccBalance,
			.01e18,
			"underlying balance"
		);
		assertEq(vault.getFloatingAmount(address(underlying)), 0);

		// this is necessary for stETH strategy (so closing account doesn't happen in same block)
		vm.roll(block.number + 1);
	}
}
