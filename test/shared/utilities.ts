import { BigNumber } from "ethers";

export const factory = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";
export const fee = 100;

export function expandTo18Decimals(n: number): BigNumber {
  return BigNumber.from(n).mul(BigNumber.from(10).pow(18));
}
