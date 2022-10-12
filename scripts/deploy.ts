import { ethers } from 'hardhat';

const uniswap_v3_position_manager = "0xC36442b4a4522E871399CD717aBDD847Ab11FE88"
const weth_address = "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619"
const spring_address = "0xf04aF3f4E4929F7CD25A751E6149A3318373d4FE"
const summer_address = "0x4D4f3715050571A447FfFa2Cd4Cf091C7014CA5c"
const autumn_address = "0x4c3bAe16c79c30eEB1004Fb03C878d89695e3a99"
const winter_address = "0xCcbA0b2bc4BAbe4cbFb6bD2f1Edc2A9e86b7845f"
const start_date = 1641340800;

async function main() {

  const SeasonalTokenFarm = await ethers.getContractFactory('SeasonalTokenFarm');
  const seasonalTokenFarm = await SeasonalTokenFarm.deploy(
    uniswap_v3_position_manager,
    spring_address,
    summer_address,
    autumn_address,
    winter_address,
    weth_address,
    start_date
  );
  await seasonalTokenFarm.deployed();

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
