import { ethers } from 'hardhat';

async function main() {

  const [owner] = await ethers.getSigners();

  const Spring = await ethers.getContractFactory('Spring');
  const spring = await Spring.deploy(owner.address);
  await spring.deployed();
  console.log('spring address is ', spring.address);

  const Summer = await ethers.getContractFactory('Summer');
  const summer = await Summer.deploy(owner.address);
  await summer.deployed();
  console.log('Summer address is ', summer.address);

  const Autumn = await ethers.getContractFactory('Autumn');
  const autumn = await Autumn.deploy(owner.address);
  await autumn.deployed();
  console.log('autumn address is ', autumn.address);

  const Winter = await ethers.getContractFactory('Winter');
  const winter = await Winter.deploy(owner.address);
  await winter.deployed();
  console.log('winter address is ', winter.address);

}


// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
