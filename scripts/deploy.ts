import { ethers } from 'hardhat';

async function main() {

  const [owner, test] = await ethers.getSigners();
  console.log('owner address is ', owner.address);
  const Spring = await ethers.getContractFactory('Spring');
  const spring = await Spring.deploy(owner.address);
  await spring.deployed();

  console.log('spring address is ', spring.address);
}


// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
