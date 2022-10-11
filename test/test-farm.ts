// eslint-disable-next-line node/no-missing-import
import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { ethers, waffle } from "hardhat";
import { expect } from "chai";
import { BigNumber, utils } from "ethers";
import {
  fixture,
  nftPositionManagerWithLiquidityToken,
  farmWithDeposit,
  farmWithDonation,
  nftPositionManagerWithFourLiquidityTokens,
  farmWithLiquidityInThreePairs
} from "./shared/fixture";
import { expandTo18Decimals, fee, factory } from "./shared/utilities";

describe("SeasonalToken", async () => {
  async function allocation_sizes(farm) {
    return ([
      await farm.springAllocationSize(),
      await farm.summerAllocationSize(),
      await farm.autumnAllocationSize(),
      await farm.winterAllocationSize()])
  }

  it("Initial total allocation size is ", async () => {
    const { farm } = await loadFixture(fixture);
    expect(await farm.getEffectiveTotalAllocationSize(0, 0, 0, 0)).to.equal(0);
  });

  it("Effective total allocation size is ", async () => {
    const { farm } = await loadFixture(fixture);
    expect(await allocation_sizes(farm)).to.deep.equal([BigNumber.from(5), BigNumber.from(6), BigNumber.from(7), BigNumber.from(8)]);
    expect(await farm.getEffectiveTotalAllocationSize(0, 0, 0, 0)).to.equal(0);
    expect(await farm.getEffectiveTotalAllocationSize(1, 0, 0, 0)).to.equal(BigNumber.from(5));
    expect(await farm.getEffectiveTotalAllocationSize(0, 1, 0, 0)).to.equal(BigNumber.from(6));
    expect(await farm.getEffectiveTotalAllocationSize(0, 0, 1, 0)).to.equal(BigNumber.from(7));
    expect(await farm.getEffectiveTotalAllocationSize(0, 0, 0, 1)).to.equal(BigNumber.from(8));
    expect(await farm.getEffectiveTotalAllocationSize(1, 1, 1, 1)).to.equal(BigNumber.from(5 + 6 + 7 + 8));
  });

  it("Reallocations Test", async () => {
    const { farm } = await loadFixture(fixture);
    expect(await farm.numberOfReAllocations()).to.equal(0);
    expect(await allocation_sizes(farm)).to.deep.equal([BigNumber.from(5), BigNumber.from(6), BigNumber.from(7), BigNumber.from(8)]);
    const availableTime = BigNumber.from(await time.latest()).add(await farm.REALLOCATION_INTERVAL());

    await time.increaseTo(availableTime.add(BigNumber.from(120 * 24 * 60 * 60)));
    expect(await farm.numberOfReAllocations()).to.equal(BigNumber.from(1));
    expect(await allocation_sizes(farm)).to.deep.equal([BigNumber.from(10), BigNumber.from(6), BigNumber.from(7), BigNumber.from(8)]);

    await time.increaseTo(BigNumber.from(await time.latest()).add(await farm.REALLOCATION_INTERVAL()));
    expect(await farm.numberOfReAllocations()).to.equal(BigNumber.from(2));
    expect(await allocation_sizes(farm)).to.deep.equal([BigNumber.from(10), BigNumber.from(12), BigNumber.from(7), BigNumber.from(8)]);

    await time.increaseTo(BigNumber.from(await time.latest()).add(await farm.REALLOCATION_INTERVAL()));
    expect(await farm.numberOfReAllocations()).to.equal(BigNumber.from(3));
    expect(await allocation_sizes(farm)).to.deep.equal([BigNumber.from(10), BigNumber.from(12), BigNumber.from(14), BigNumber.from(8)]);

    await time.increaseTo(BigNumber.from(await time.latest()).add(await farm.REALLOCATION_INTERVAL()));
    expect(await farm.numberOfReAllocations()).to.equal(BigNumber.from(4));
    expect(await allocation_sizes(farm)).to.deep.equal([BigNumber.from(5), BigNumber.from(6), BigNumber.from(7), BigNumber.from(8)]);
  });

  describe("nftPositionManager", function () {

    it("Creative Liqudity Token Test", async () => {
      const { owner, winterToken, wETH, nftPositionManager } = await loadFixture(fixture);
      expect(await nftPositionManager.numberOfTokens()).to.equal(0);
      const liquidityTokenId = nftPositionManager.numberOfTokens();
      const tx = await nftPositionManager.createLiquidityToken(
        owner.address,
        wETH.address,
        winterToken.address,
        fee,
        -887272,
        887272,
        10000000000
      );
      await tx.wait();

      expect(await nftPositionManager.numberOfTokens()).to.equal(1);
    });

    it("Deposit liquidity token test", async () => {
      const { owner, farm } = await loadFixture(fixture);
      const nftPositionManager = await nftPositionManagerWithLiquidityToken();
      const liquidityTokenId = await nftPositionManager.numberOfTokens() - 1;
      const position = await nftPositionManager.positions(liquidityTokenId);
      expect(position.fee).to.equal(fee);

      const tx = await nftPositionManager.selfSafeTransferFrom(
        owner.address,
        farm.address, liquidityTokenId
      )
      await tx.wait();

      expect(await farm.balanceOf(owner.address)).to.equal(1);
      expect(await farm.tokenOfOwnerByIndex(owner.address, 0)).to.equal(liquidityTokenId);
    });

    it("Deposit revert wETH not in trading pair", async () => {
      const { owner, farm, nftPositionManager, springToken, summerToken } = await loadFixture(fixture);
      const tx = await nftPositionManager.createLiquidityToken(
        owner.address,
        springToken.address,
        summerToken.address,
        fee,
        -887272,
        887272,
        10000000000
      );
      await tx.wait();

      await expect(nftPositionManager.selfSafeTransferFrom(
        owner.address,
        farm.address,
        0)
      ).to.be.revertedWith(
        "Invalid trading pair"
      );
    });

    it("Deposit revert seasonal token not in trading pair", async () => {
      const { owner, farm, nftPositionManager, wETH } = await loadFixture(fixture);
      const tx = await nftPositionManager.createLiquidityToken(
        owner.address,
        wETH.address,
        wETH.address,
        fee,
        -887272,
        887272,
        10000000000
      );

      await tx.wait();
      await expect(nftPositionManager.selfSafeTransferFrom(owner.address, farm.address, 0)).to.be.revertedWith(
        "Invalid trading pair"
      );
    });

    it("Deposit revert not full range", async () => {
      const { owner, farm, nftPositionManager, springToken, wETH } = await loadFixture(fixture);
      const tx = await nftPositionManager.createLiquidityToken(
        owner.address,
        springToken.address,
        wETH.address,
        fee,
        -887100,
        887272,
        10000000000
      );
      await tx.wait();

      const tx1 = await nftPositionManager.createLiquidityToken(
        owner.address,
        springToken.address,
        wETH.address,
        fee,
        -887272,
        887100,
        10000000000
      );
      await tx1.wait();

      await expect(nftPositionManager.selfSafeTransferFrom(owner.address, farm.address, 0)).to.be.revertedWith(
        "Liquidity must cover full range of prices"
      );
      await expect(nftPositionManager.selfSafeTransferFrom(owner.address, farm.address, 1)).to.be.revertedWith(
        "Liquidity must cover full range of prices"
      );
    });

    it("Deposit revert wrong fee tier", async () => {
      const { owner, farm, nftPositionManager, wETH, springToken } = await loadFixture(fixture);
      const tx = await nftPositionManager.createLiquidityToken(
        owner.address,
        springToken.address,
        wETH.address,
        120,
        -887272,
        887272,
        10000000000
      );
      await tx.wait();

      await expect(nftPositionManager.selfSafeTransferFrom(owner.address, farm.address, 0)).to.be.revertedWith(
        "Fee tier must be 0.01%"
      );
    });

    it("Deposit revert not uniswap v3 token", async () => {
      const { owner, farm, springToken, wETH } = await loadFixture(fixture);
      const NftPositionManager2 = await ethers.getContractFactory('TestNftPositionManager');
      const nftPositionManager2 = await NftPositionManager2.deploy(factory);
      await nftPositionManager2.deployed();

      const tx = await nftPositionManager2.createLiquidityToken(
        owner.address,
        wETH.address,
        springToken.address,
        fee,
        -887272,
        887272,
        10000000000
      );
      await tx.wait();
      await expect(nftPositionManager2.selfSafeTransferFrom(owner.address, farm.address, 0)).to.be.revertedWith(
        "Only Uniswap v3 liquidity tokens can be deposited"
      );
    });
  });

  describe("Farm", function () {
    it("Donate Test", async () => {
      const { owner, winterToken } = await loadFixture(fixture);
      const farm = await farmWithDeposit();

      const tx = await winterToken.setBalance(owner.address, utils.parseUnits("1.0"));
      await tx.wait();
      const tx1 = await winterToken.approve(farm.address, utils.parseUnits("1.0"));
      await tx1.wait();
      const tx2 = await farm.receiveSeasonalTokens(owner.address, winterToken.address, utils.parseUnits("1.0"));
      await tx2.wait();

      expect(await winterToken.balanceOf(owner.address)).to.equal(0);
      expect(await winterToken.balanceOf(farm.address)).to.equal(expandTo18Decimals(1));
    });

    it("Revert donate not seasonal token Test", async () => {
      const { owner, wETH } = await loadFixture(fixture);
      const farm = await farmWithDeposit();

      const tx = await wETH.setBalance(owner.address, utils.parseUnits("1.0"));
      await tx.wait();
      const tx1 = await wETH.approve(farm.address, utils.parseUnits("1.0"));
      await tx1.wait();

      await expect(farm.receiveSeasonalTokens(owner.address, wETH.address, utils.parseUnits("1.0"))).to.be.revertedWith(
        "Only Seasonal Tokens can be donated"
      );
    });

    it("Revert donate not owner", async () => {
      const { owner, other, winterToken } = await loadFixture(fixture);
      const farm = await farmWithDeposit();

      const tx = await winterToken.setBalance(owner.address, utils.parseUnits("1.0"));
      await tx.wait();
      const tx1 = await winterToken.approve(farm.address, utils.parseUnits("1.0"));
      await tx1.wait();

      await expect(farm.connect(other).receiveSeasonalTokens(owner.address, winterToken.address, utils.parseUnits("1.0"))).to.be.revertedWith(
        "Tokens must be donated by the address that owns them."
      );
    });

    it("Tokens available for harvest", async () => {
      const { springToken, winterToken } = await loadFixture(fixture);
      const nftPositionManager = await nftPositionManagerWithLiquidityToken();
      const farm = await farmWithDonation();
      const liquidityTokenId = (await nftPositionManager.numberOfTokens()).sub(BigNumber.from(1));

      expect(await farm.cumulativeTokensFarmedPerUnitLiquidity(winterToken.address, winterToken.address)).to.gt(0);
      expect(await farm.cumulativeTokensFarmedPerUnitLiquidity(springToken.address, winterToken.address)).to.equal(0);
      expect(await farm.cumulativeTokensFarmedPerUnitLiquidity(winterToken.address, springToken.address)).to.equal(0);
      expect(await farm.getPayoutSizes(liquidityTokenId)[3]).to.not.equal(0);
    });

    it("Harvest Test", async () => {
      const { owner, winterToken } = await loadFixture(fixture);
      const nftPositionManager = await nftPositionManagerWithLiquidityToken();
      const farm = await farmWithDonation();
      const liquidityTokenId =
        (await nftPositionManager.numberOfTokens()).sub(BigNumber.from(1));

      const tx = await farm.harvest(liquidityTokenId);
      await tx.wait();

      expect(((await winterToken.balanceOf(owner.address)).sub(utils.parseEther("1.0")).abs())).to.be.lt(BigNumber.from(10));
      expect(await winterToken.balanceOf(farm.address)).to.be.lt(BigNumber.from(10));
      expect(await farm.getPayoutSizes(liquidityTokenId)).to.deep.equal([BigNumber.from(0), BigNumber.from(0), BigNumber.from(0), BigNumber.from(0)]);
    });

    it("Harvest revert not owner", async () => {
      const { other } = await loadFixture(fixture);
      const nftPositionManager = await nftPositionManagerWithLiquidityToken();
      const farm = await farmWithDonation();
      const liquidityTokenId =
        (await nftPositionManager.numberOfTokens()).sub(BigNumber.from(1));

      await expect(farm.connect(other).harvest(liquidityTokenId)).to.be.reverted;
    });

    it("Withdraw", async () => {
      const { owner, winterToken } = await loadFixture(fixture);
      const nftPositionManager = await nftPositionManagerWithLiquidityToken();
      const farm = await farmWithDonation();
      const liquidityTokenId =
        (await nftPositionManager.numberOfTokens()).sub(BigNumber.from(1));

      expect(await farm.balanceOf(owner.address)).to.equal(BigNumber.from(1));

      await time.increaseTo(BigNumber.from(await time.latest()).add((await farm.WITHDRAWAL_UNAVAILABLE_DAYS()).mul(BigNumber.from(24 * 60 * 60))));

      const tx = await farm.withdraw(liquidityTokenId);
      await tx.wait();

      expect(await farm.balanceOf(owner.address)).equal(0);
    });

    it("Revert withdraw not owner", async () => {
      const { owner, other, winterToken } = await loadFixture(fixture);
      const nftPositionManager = await nftPositionManagerWithLiquidityToken();
      const farm = await farmWithDonation();
      const liquidityTokenId =
        (await nftPositionManager.numberOfTokens()).sub(BigNumber.from(1));

      await time.increaseTo(BigNumber.from(await time.latest()).add((await farm.WITHDRAWAL_UNAVAILABLE_DAYS()).mul(BigNumber.from(24 * 60 * 60))));

      await expect(farm.connect(other).withdraw(liquidityTokenId)).to.be.reverted;
    });

    it("Revert withdrawal unavailable", async () => {
      const { owner, other, winterToken } = await loadFixture(fixture);
      const nftPositionManager = await nftPositionManagerWithLiquidityToken();
      const farm = await farmWithDonation();
      const liquidityTokenId =
        (await nftPositionManager.numberOfTokens()).sub(BigNumber.from(1));

      await expect(farm.connect(other).withdraw(liquidityTokenId)).to.be.reverted;
    });

    it("Next withdrawal time:", async () => {
      const { owner, other, winterToken } = await loadFixture(fixture);
      const nftPositionManager = await nftPositionManagerWithLiquidityToken();
      const farm = await farmWithDonation();
      const liquidityTokenId =
        (await nftPositionManager.numberOfTokens()).sub(BigNumber.from(1));

      const withdrawalUnavailableDays = await farm.WITHDRAWAL_UNAVAILABLE_DAYS();
      const withdrawalAvailableDays = await farm.WITHDRAWAL_AVAILABLE_DAYS();
      let withdrawalTime = (await farm.liquidityTokens(liquidityTokenId))[2].add(withdrawalUnavailableDays.mul(BigNumber.from(24 * 60 * 60)));
      const blockTime = await time.latest();

      while (withdrawalTime.lte(BigNumber.from(blockTime))) {
        withdrawalTime = (withdrawalTime.add(withdrawalUnavailableDays.add(withdrawalAvailableDays))).mul(BigNumber.from(24 * 60 * 60));
      }
      expect(await farm.nextWithdrawalTime(liquidityTokenId)).to.equal(withdrawalTime);
    });

    it("Harvest from farm with donations and liquidity in three pairs", async () => {
      const { owner, springToken, summerToken, autumnToken } = await loadFixture(fixture);
      const farm = await farmWithLiquidityInThreePairs();

      const tx = await springToken.setBalance(owner.address, utils.parseEther("1.0"));
      await tx.wait();
      const tx1 = await springToken.approve(farm.address, utils.parseEther("1.0"));
      await tx1.wait();
      const tx2 = await farm.receiveSeasonalTokens(owner.address, springToken.address, utils.parseEther("1.0"));
      await tx2.wait();

      expect(await springToken.balanceOf(owner.address)).to.equal(0);
      expect(await springToken.balanceOf(farm.address)).to.equal(utils.parseEther("1.0"));

      const tx3 = await summerToken.setBalance(owner.address, utils.parseEther("1.0"));
      await tx3.wait();
      const tx4 = await summerToken.approve(farm.address, utils.parseEther("1.0"));
      await tx4.wait();
      const tx5 = await farm.receiveSeasonalTokens(owner.address, summerToken.address, utils.parseEther("1.0"));
      await tx5.wait();

      expect(await summerToken.balanceOf(owner.address)).to.equal(0);
      expect(await summerToken.balanceOf(farm.address)).to.equal(utils.parseEther("1.0"));

      const tx6 = await autumnToken.setBalance(owner.address, utils.parseEther("1.0"));
      await tx6.wait();
      const tx7 = await autumnToken.approve(farm.address, utils.parseEther("1.0"));
      await tx7.wait();
      const tx8 = await farm.receiveSeasonalTokens(owner.address, autumnToken.address, utils.parseEther("1.0"));
      await tx8.wait();

      expect(await autumnToken.balanceOf(owner.address)).to.equal(0);
      expect(await autumnToken.balanceOf(farm.address)).to.equal(utils.parseEther("1.0"));

    });

    it("Withdraw from farm with liquidity in three pairs", async function () {
      const { owner } = await loadFixture(fixture);
      const farm = await farmWithLiquidityInThreePairs();

      expect(await farm.balanceOf(owner.address)).to.equal(BigNumber.from(3));
      expect(await farm.tokenOfOwnerByIndex(owner.address, 0)).to.equal(0);
      expect(await farm.tokenOfOwnerByIndex(owner.address, 1)).to.equal(BigNumber.from(1));
      expect(await farm.tokenOfOwnerByIndex(owner.address, 2)).to.equal(BigNumber.from(2));

      await time.increaseTo(BigNumber.from(await time.latest()).add((await farm.WITHDRAWAL_UNAVAILABLE_DAYS()).mul(BigNumber.from(24 * 60 * 60))));
      const tx = await farm.withdraw(0);
      await tx.wait();

      expect(await farm.balanceOf(owner.address)).to.equal(BigNumber.from(2));
      expect(await farm.tokenOfOwnerByIndex(owner.address, 0)).to.equal(BigNumber.from(2));
      expect(await farm.tokenOfOwnerByIndex(owner.address, 1)).to.equal(BigNumber.from(1));

      const tx1 = await farm.withdraw(1);
      await tx1.wait();

      expect(await farm.balanceOf(owner.address)).to.equal(BigNumber.from(1));
      expect(await farm.tokenOfOwnerByIndex(owner.address, 0)).to.equal(BigNumber.from(2));

    });




  });

});
