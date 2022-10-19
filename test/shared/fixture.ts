import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { BigNumber, utils } from "ethers";
import { ethers } from "hardhat";

import { fee } from "./constants";

export async function fixture() {

  const [owner, other] = await ethers.getSigners();
  const startTime = await time.latest() + 120 * 24 * 60 * 60;

  const SpringToken = await ethers.getContractFactory('TestSpringToken');
  const springToken = await SpringToken.deploy();
  await springToken.deployed();

  const SummerToken = await ethers.getContractFactory('TestSpringToken');
  const summerToken = await SummerToken.deploy();
  await summerToken.deployed();

  const AutumnToken = await ethers.getContractFactory('TestSpringToken');
  const autumnToken = await AutumnToken.deploy();
  await autumnToken.deployed();

  const WinterToken = await ethers.getContractFactory('TestSpringToken');
  const winterToken = await WinterToken.deploy();
  await winterToken.deployed();

  const WETH = await ethers.getContractFactory('TestSpringToken');
  const wETH = await WETH.deploy();
  await wETH.deployed();

  const NftPositionManager = await ethers.getContractFactory('TestNftPositionManager');
  const nftPositionManager = await NftPositionManager.deploy();
  await nftPositionManager.deployed();

  const Farm = await ethers.getContractFactory('SeasonalTokenFarm');
  const farm = await Farm.deploy(
    nftPositionManager.address,
    springToken.address,
    summerToken.address,
    autumnToken.address,
    winterToken.address,
    wETH.address,
    startTime
  );
  await farm.deployed();

  return {
    owner,
    other,
    farm,
    nftPositionManager,
    springToken,
    summerToken,
    autumnToken,
    winterToken,
    wETH
  };
}

export async function nftPositionManagerWithLiquidityToken() {
  const { owner, nftPositionManager, wETH, winterToken } = await loadFixture(fixture);
  const tx = await nftPositionManager.createLiquidityToken(owner.address, wETH.address, winterToken.address, fee,
    -887272, 887272, 10000000000);
  await tx.wait();

  return nftPositionManager;
}

export async function farmWithDeposit() {
  const { owner, farm } = await loadFixture(fixture);
  const nftPositionManager = await nftPositionManagerWithLiquidityToken();
  const liquidityTokenId = (await nftPositionManager.numberOfTokens()).sub(BigNumber.from(1));
  const tx = await nftPositionManager.safeTransferFrom(
    owner.address,
    farm.address,
    liquidityTokenId
  );
  await tx.wait();
  return farm;
}
export async function farmWithDonation() {
  const { owner, winterToken } = await loadFixture(fixture);
  const farm = await farmWithDeposit();

  const tx = await winterToken.setBalance(owner.address, utils.parseEther("1.0"));
  await tx.wait();
  const tx1 = await winterToken.approve(farm.address, utils.parseEther("1.0"));
  await tx1.wait();

  const tx2 = await farm.receiveSeasonalTokens(owner.address, winterToken.address, utils.parseEther("1.0"));
  await tx2.wait();

  return farm;
}

export async function allocationSizes(farm) {
  return ([
    await farm.springAllocationSize(),
    await farm.summerAllocationSize(),
    await farm.autumnAllocationSize(),
    await farm.winterAllocationSize()])
}

export async function nftPositionManagerWithFourLiquidityTokens() {
  const { owner, nftPositionManager, wETH, springToken, summerToken, autumnToken, winterToken } = await loadFixture(fixture);
  const tx1 = await nftPositionManager.createLiquidityToken(
    owner.address,
    wETH.address,
    springToken.address,
    fee,
    -887272,
    887272,
    10000000000
  );
  await tx1.wait();

  const tx2 = await nftPositionManager.createLiquidityToken(
    owner.address,
    wETH.address,
    summerToken.address,
    fee,
    -887272,
    887272,
    10000000000
  );
  await tx2.wait();
  const tx3 = await nftPositionManager.createLiquidityToken(
    owner.address,
    wETH.address,
    autumnToken.address,
    fee,
    -887272,
    887272,
    10000000000
  );
  await tx3.wait();
  const tx4 = await nftPositionManager.createLiquidityToken(
    owner.address,
    wETH.address,
    winterToken.address,
    fee,
    -887272,
    887272,
    10000000000
  );
  await tx4.wait();

  return nftPositionManager;
}

export async function farmWithLiquidityInThreePairs() {
  const { owner, farm } = await loadFixture(fixture);
  const nftPositionManager = await nftPositionManagerWithFourLiquidityTokens();
  await nftPositionManager.safeTransferFrom(owner.address, farm.address, 0);
  await nftPositionManager.safeTransferFrom(owner.address, farm.address, 1);
  await nftPositionManager.safeTransferFrom(owner.address, farm.address, 2);
  return farm;
}





