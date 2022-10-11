import { BigNumber } from "ethers";
import { ethers } from "hardhat";

export const springToken = "0xa9fb5322BEedc24944a13E3cf25e447bFF8ef610";
export const summerToken = "0x58D4533703A50F513308492e86C9e4589146E242";
export const autumnToken = "0x0fB80f73D3d80227d57faD1630E12b939f6A4B73";
export const winterToken = "0xC96185b5dFf9393709d310a4a98326276bE84b5E";
export const wETH = "";
export const factory = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";
export const fee = 100;

export function expandTo18Decimals(n: number): BigNumber {
  return BigNumber.from(n).mul(BigNumber.from(10).pow(18));
}

export function expandToDecimals(n: number, d: number): BigNumber {
  return BigNumber.from(n).mul(BigNumber.from(10).pow(d));
}

export async function mineBlock(
  provider: typeof ethers.provider,
  timestamp: number
): Promise<void> {
  await provider.send("evm_setNextBlockTimestamp", [timestamp]);
}

export async function increaseTime(timeToAdd: number) {
  await ethers.provider.send("evm_increaseTime", [timeToAdd]);
  await ethers.provider.send("evm_mine", []);
}

export function sleep(second: number) {
  return new Promise((resolve) => setTimeout(resolve, second * 1000));
}
