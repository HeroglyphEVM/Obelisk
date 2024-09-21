// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "test/base/BaseTest.t.sol";

import { MockERC20 } from "test/mock/contract/MockERC20.t.sol";
import { InterestManager, IInterestManager, IDripVault, IApxETH, IPirexEth } from "src/services/InterestManager.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IWETH } from "src/interfaces/IWETH.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract InterestManagerTest is BaseTest {
  uint24 private constant DAI_POOL_FEE = 500;

  address[] private ADDRESSES;
  uint128[] private WEIGHTS;

  address private user;
  address private owner;
  address private gaugeController;
  address private mockDripVaultETH;
  address private mockDripVaultDAI;
  address private mockSwapRouter;
  address private mockPirexEth;

  MockERC20 private dai;
  MockERC20 private axpETH;
  address private weth;

  InterestManagerHarness private underTest;

  function setUp() external {
    delete ADDRESSES;
    delete WEIGHTS;
    _createVariables();
    _createMockCalls();

    underTest = new InterestManagerHarness(
      owner, gaugeController, mockDripVaultETH, mockDripVaultDAI, mockSwapRouter, address(weth)
    );
  }

  function _createVariables() internal {
    user = generateAddress("user", 100e18);
    owner = generateAddress("owner");
    gaugeController = generateAddress("gaugeController");
    mockDripVaultETH = generateAddress("mockDripVaultETH");
    mockDripVaultDAI = generateAddress("mockDripVaultDAI");
    mockSwapRouter = generateAddress("mockSwapRouter");
    mockPirexEth = generateAddress("mockPirexEth");
    weth = generateAddress("WETH");

    axpETH = new MockERC20("ApxETH", "ApxETH", 18);
    dai = new MockERC20("DAI", "DAI", 18);

    vm.label(address(axpETH), "axpETH");
    vm.label(address(dai), "DAI");
  }

  function _createMockCalls() internal {
    vm.mockCall(mockDripVaultDAI, abi.encodeWithSelector(IDripVault.getInputToken.selector), abi.encode(address(dai)));
    vm.mockCall(
      mockDripVaultETH, abi.encodeWithSelector(IDripVault.getOutputToken.selector), abi.encode(address(axpETH))
    );
    vm.mockCall(mockDripVaultDAI, abi.encodeWithSelector(IDripVault.claim.selector), abi.encode(0));
    vm.mockCall(mockDripVaultETH, abi.encodeWithSelector(IDripVault.claim.selector), abi.encode(0));
    vm.mockCall(address(axpETH), abi.encodeWithSelector(IApxETH.pirexEth.selector), abi.encode(mockPirexEth));

    vm.mockCall(mockPirexEth, abi.encodeWithSelector(IPirexEth.deposit.selector), abi.encode(0, 0));
    vm.mockCall(address(weth), abi.encodeWithSelector(IWETH.withdraw.selector), abi.encode(true));
  }

  function test_constructor_thenSetsVariables() external {
    underTest = new InterestManagerHarness(
      owner, gaugeController, mockDripVaultETH, mockDripVaultDAI, mockSwapRouter, address(weth)
    );

    assertEq(underTest.owner(), owner);
    assertEq(underTest.gaugeController(), gaugeController);
    assertEq(address(underTest.DRIP_VAULT_ETH()), mockDripVaultETH);
    assertEq(address(underTest.DRIP_VAULT_DAI()), mockDripVaultDAI);
    assertEq(underTest.SWAP_ROUTER(), mockSwapRouter);

    assertEq(address(underTest.DAI()), address(dai));
    assertEq(address(underTest.WETH()), address(weth));
    assertEq(address(underTest.PIREX_ETH()), mockPirexEth);
    assertEq(address(underTest.APX_ETH()), address(axpETH));
    assertEq(underTest.epochId(), 0);
    assertEq(underTest.nextApplyGaugesUnlock(), 0);
  }

  function test_applyGauges_asNotGaugeController_thenReverts() external {
    vm.expectRevert(abi.encodeWithSelector(IInterestManager.NotGaugeController.selector));
    underTest.applyGauges(new address[](0), new uint128[](0));
  }

  function test_applyGauges_whenLocked_thenReverts() external prankAs(gaugeController) {
    underTest.applyGauges(new address[](1), new uint128[](1));

    skip(5.9 days);
    vm.expectRevert(abi.encodeWithSelector(IInterestManager.ApplyGaugesLocked.selector));
    underTest.applyGauges(new address[](1), new uint128[](1));
  }

  function test_applyGauges_whenInvalidInputLength_thenReverts() external prankAs(gaugeController) {
    vm.expectRevert(abi.encodeWithSelector(IInterestManager.InvalidInputLength.selector));
    underTest.applyGauges(new address[](1), new uint128[](0));

    vm.expectRevert(abi.encodeWithSelector(IInterestManager.InvalidInputLength.selector));
    underTest.applyGauges(new address[](0), new uint128[](1));
  }

  function test_applyGauges_thenUpdatesGauges() external prankAs(gaugeController) {
    ADDRESSES.push(generateAddress("pool1"));
    ADDRESSES.push(generateAddress("pool2"));
    WEIGHTS.push(1e18);
    WEIGHTS.push(2e18);

    expectExactEmit();
    emit IInterestManager.EpochIntialized(1, ADDRESSES, WEIGHTS, WEIGHTS[0] + WEIGHTS[1]);

    underTest.applyGauges(ADDRESSES, WEIGHTS);

    (uint128 totalRewards, uint128 totalWeight, address[] memory megapools) = underTest.getEpochData(1);

    assertEq(totalRewards, 0);
    assertEq(totalWeight, WEIGHTS[0] + WEIGHTS[1]);
    assertEq(megapools, ADDRESSES);
    assertEq(underTest.nextApplyGaugesUnlock(), block.timestamp + underTest.BLOCK_APPLY_GAUGES_TIMER());
    assertEq(underTest.epochId(), 1);
    assertEq(underTest.getMegapoolWeight(1, ADDRESSES[0]), WEIGHTS[0]);
    assertEq(underTest.getMegapoolWeight(1, ADDRESSES[1]), WEIGHTS[1]);
  }

  function test_endEpoch_thenAssignRewardsAndIncreasesEpochId() external prankAs(gaugeController) {
    ADDRESSES.push(generateAddress("pool1"));
    ADDRESSES.push(generateAddress("pool2"));
    WEIGHTS.push(1e18);
    WEIGHTS.push(2e18);

    underTest.applyGauges(ADDRESSES, WEIGHTS);

    uint256 reward = 3e18;
    uint256 expectingForPool1 = (reward * WEIGHTS[0]) / (WEIGHTS[0] + WEIGHTS[1]);
    uint256 expectingForPool2 = reward - expectingForPool1;

    vm.mockCall(mockDripVaultETH, abi.encodeWithSelector(IDripVault.claim.selector), abi.encode(reward));

    vm.expectEmit(true, false, false, false);
    emit IInterestManager.RewardAssigned(ADDRESSES[0], expectingForPool1, expectingForPool1);
    vm.expectEmit(true, false, false, false);
    emit IInterestManager.RewardAssigned(ADDRESSES[1], expectingForPool2, expectingForPool2);
    expectExactEmit();
    emit IInterestManager.EpochEnded(1);

    underTest.exposed_endEpoch();
    assertEq(underTest.epochId(), 2);

    (uint128 totalRewards,,) = underTest.getEpochData(1);
    assertEq(totalRewards, reward);

    assertEqDecimalEpsilonBelow(underTest.getRewards(ADDRESSES[0]), expectingForPool1, 18, 1e4);
    assertEqDecimalEpsilonBelow(underTest.getRewards(ADDRESSES[1]), expectingForPool2, 18, 1e4);
  }

  function test_claim_whenNoRewards_thenReturnsZero() external prankAs(generateAddress("Random")) {
    vm.mockCallRevert(address(axpETH), abi.encodeWithSelector(MockERC20.transfer.selector), abi.encode(false));
    assertEq(underTest.claim(), 0);
  }

  function test_claim_whenOnlyPendingRewards_thenSendsPendingRewards() external prankAs(gaugeController) {
    ADDRESSES.push(generateAddress("pool1"));
    WEIGHTS.push(1e18);
    uint256 reward = 3e18;

    axpETH.mint(address(underTest), reward);

    underTest.applyGauges(ADDRESSES, WEIGHTS);
    underTest.exposed_setTotalEpochRewards(uint128(reward));

    underTest.exposed_endEpoch();
    assertEq(underTest.getRewards(ADDRESSES[0]), reward);

    changePrank(ADDRESSES[0]);
    expectExactEmit();
    emit IInterestManager.RewardClaimed(ADDRESSES[0], reward);
    uint256 claimed = underTest.claim();

    assertEq(claimed, reward);
    assertEq(underTest.getRewards(ADDRESSES[0]), 0);
  }

  function test_claim_whenETHClaim_thenSendsClaimedETHFromVault() external prankAs(gaugeController) {
    ADDRESSES.push(generateAddress("pool1"));
    WEIGHTS.push(1e18);
    uint256 reward = 3e18;

    axpETH.mint(address(underTest), reward);
    underTest.applyGauges(ADDRESSES, WEIGHTS);

    vm.mockCall(mockDripVaultETH, abi.encodeWithSelector(IDripVault.claim.selector), abi.encode(reward));

    vm.expectRevert(abi.encodeWithSelector(IInterestManager.RealTimeRewards.selector, reward));
    underTest.getRealTimeRewards_Reverting(ADDRESSES[0]);
    assertEq(underTest.getRewards(ADDRESSES[0]), 0);

    changePrank(ADDRESSES[0]);
    expectExactEmit();
    emit IInterestManager.RewardClaimed(ADDRESSES[0], reward);
    uint256 claimed = underTest.claim();

    assertEq(claimed, reward);
    assertEq(underTest.getRewards(ADDRESSES[0]), 0);
  }

  function test_claim_whenDaiClaim_thenSwapDaiToApxETHAndSends() external prankAs(gaugeController) {
    ADDRESSES.push(generateAddress("pool1"));
    WEIGHTS.push(1e18);
    uint256 daiReward = 12_000e18;
    uint256 reward = 3e18;

    underTest.applyGauges(ADDRESSES, WEIGHTS);

    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
      tokenIn: address(dai),
      tokenOut: address(weth),
      fee: DAI_POOL_FEE,
      recipient: address(underTest),
      deadline: block.timestamp,
      amountIn: daiReward,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0
    });

    dai.mint(address(underTest), daiReward);
    axpETH.mint(address(underTest), reward);

    vm.mockCall(
      mockSwapRouter, abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params), abi.encode(reward)
    );
    vm.mockCall(address(weth), abi.encodeWithSelector(IWETH.withdraw.selector, reward), abi.encode(true));
    vm.mockCall(
      mockPirexEth,
      reward,
      abi.encodeWithSelector(IPirexEth.deposit.selector, address(underTest), true),
      abi.encode(reward, 0)
    );

    vm.expectRevert(abi.encodeWithSelector(IInterestManager.RealTimeRewards.selector, reward));
    underTest.getRealTimeRewards_Reverting(ADDRESSES[0]);
    assertEq(underTest.getRewards(ADDRESSES[0]), 0);

    changePrank(ADDRESSES[0]);
    expectExactEmit();
    emit IInterestManager.RewardClaimed(ADDRESSES[0], reward);
    uint256 claimed = underTest.claim();

    assertEq(claimed, reward);
    assertEq(underTest.getRewards(ADDRESSES[0]), 0);
    //Since we are mocking the swap router, allowance won't be consumed.
    assertEq(dai.allowance(address(underTest), mockSwapRouter), daiReward);
  }

  function test_claim_thenSendsRewards() external prankAs(gaugeController) {
    ADDRESSES.push(generateAddress("pool1"));
    WEIGHTS.push(1e18);

    uint256 daiReward = 12_000e18;
    uint256 ethReward = 3.3e18;
    uint256 convertedDaiReward = 2.1e18;
    uint256 reward = convertedDaiReward + ethReward;

    underTest.applyGauges(ADDRESSES, WEIGHTS);

    dai.mint(address(underTest), daiReward);
    axpETH.mint(address(underTest), reward);

    vm.mockCall(mockDripVaultETH, abi.encodeWithSelector(IDripVault.claim.selector), abi.encode(ethReward));
    vm.mockCall(
      mockSwapRouter, abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector), abi.encode(convertedDaiReward)
    );
    vm.mockCall(address(weth), abi.encodeWithSelector(IWETH.withdraw.selector), abi.encode(true));
    vm.mockCall(mockPirexEth, abi.encodeWithSelector(IPirexEth.deposit.selector), abi.encode(convertedDaiReward, 0));

    vm.expectRevert(abi.encodeWithSelector(IInterestManager.RealTimeRewards.selector, reward));
    underTest.getRealTimeRewards_Reverting(ADDRESSES[0]);
    assertEq(underTest.getRewards(ADDRESSES[0]), 0);

    changePrank(ADDRESSES[0]);
    expectExactEmit();
    emit IInterestManager.RewardClaimed(ADDRESSES[0], reward);
    uint256 claimed = underTest.claim();

    (uint128 totalRewards,,) = underTest.getEpochData(underTest.epochId());

    assertEq(totalRewards, reward);
    assertEq(claimed, reward);
    assertEq(underTest.getRewards(ADDRESSES[0]), 0);
  }

  function test_assignRewardToMegapool_thenAssignsReward() external prankAs(gaugeController) {
    ADDRESSES.push(generateAddress("pool1"));
    WEIGHTS.push(1e18);

    uint128 reward = 10e18;

    underTest.applyGauges(ADDRESSES, WEIGHTS);
    underTest.exposed_setTotalEpochRewards(reward);

    expectExactEmit();
    emit IInterestManager.RewardAssigned(ADDRESSES[0], reward, reward);
    underTest.exposed_assignRewardToMegapool(ADDRESSES[0]);

    assertEq(underTest.getRewards(ADDRESSES[0]), reward);
    assertEq(underTest.exposed_getClaimedRewards(ADDRESSES[0]), reward);
  }

  function test_assignRewardToMegapool_whenNoRewardOnSecondCall_thenDoesNotIncrease() external prankAs(gaugeController) {
    ADDRESSES.push(generateAddress("pool1"));
    WEIGHTS.push(1e18);

    uint128 reward = 10e18;

    underTest.applyGauges(ADDRESSES, WEIGHTS);
    underTest.exposed_setTotalEpochRewards(reward);

    expectExactEmit();
    emit IInterestManager.RewardAssigned(ADDRESSES[0], reward, reward);
    underTest.exposed_assignRewardToMegapool(ADDRESSES[0]);
    underTest.exposed_assignRewardToMegapool(ADDRESSES[0]);

    assertEq(underTest.getRewards(ADDRESSES[0]), reward);
    assertEq(underTest.exposed_getClaimedRewards(ADDRESSES[0]), reward);
  }

  function test_setGaugeController_asNonOwner_thenReverts() external prankAs(user) {
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
    underTest.setGaugeController(generateAddress("NewGaugeController"));
  }

  function test_setGaugeController_thenSetsGaugeController() external prankAs(owner) {
    address newGaugeController = generateAddress("NewGaugeController");

    expectExactEmit();
    emit IInterestManager.GaugeControllerSet(newGaugeController);
    underTest.setGaugeController(newGaugeController);
    assertEq(underTest.gaugeController(), newGaugeController);
  }

  function test_fizz_DistributionFormula_thenSucceedUnderTolerence(uint64[13] memory _weights, uint128 _totalRewards)
    external
    prankAs(gaugeController)
  {
    _totalRewards = uint128(bound(_totalRewards, 0.001e18, 10_000e18));

    uint128 weight;
    for (uint256 i = 0; i < _weights.length; i++) {
      weight = uint128(bound(_weights[i], 0.01e18, type(uint64).max));
      WEIGHTS.push(weight);
      ADDRESSES.push(generateAddress(string.concat("pool-", Strings.toString(i))));
    }

    axpETH.mint(address(underTest), _totalRewards);

    underTest.applyGauges(ADDRESSES, WEIGHTS);
    underTest.exposed_setTotalEpochRewards(_totalRewards);

    for (uint256 i = 0; i < ADDRESSES.length; i++) {
      changePrank(ADDRESSES[i]);
      underTest.claim();
    }

    (uint128 totalRewards,,) = underTest.getEpochData(underTest.epochId());
    assertEq(totalRewards, _totalRewards);

    assertLt(axpETH.balanceOf(address(underTest)), 1e6);
  }
}

contract InterestManagerHarness is InterestManager {
  constructor(
    address _owner,
    address _gaugeController,
    address _dripVaultETH,
    address _dripVaultDAI,
    address _swapRouter,
    address _weth
  ) InterestManager(_owner, _gaugeController, _dripVaultETH, _dripVaultDAI, _swapRouter, _weth) { }

  function exposed_endEpoch() external {
    _endEpoch();
  }

  function exposed_setTotalEpochRewards(uint128 _rewards) external {
    epochs[epochId].totalRewards = _rewards;
  }

  function exposed_assignRewardToMegapool(address _megapool) external {
    _assignRewardToMegapool(epochs[epochId], _megapool);
  }

  function exposed_getClaimedRewards(address _megapool) external view returns (uint128 claimed_) {
    return epochs[epochId].megapoolClaims[_megapool];
  }
}
