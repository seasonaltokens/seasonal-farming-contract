import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import * as dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
import "hardhat-gas-reporter";
import "solidity-coverage";

dotenv.config();

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const LOW_OPTIMIZER_COMPILER_SETTINGS = {
  version: '0.7.6',
  settings: {
    evmVersion: 'istanbul',
    optimizer: {
      enabled: true,
      runs: 2_000,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}

const DEFAULT_COMPILER_SETTINGS = {
  version: '0.7.6',
  settings: {
    evmVersion: 'istanbul',
    optimizer: {
      enabled: true,
      runs: 1_000_000,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [DEFAULT_COMPILER_SETTINGS],
    overrides: {
      'contracts/NonFungiblePositionManager.sol': LOW_OPTIMIZER_COMPILER_SETTINGS,
    },
  },
  networks: {
    hardhat: {
      gas: 15000000,
      gasPrice: 875000000,
      blockGasLimit: 15000000,
      allowUnlimitedContractSize: true,
    },
    mainnet: {
      url: process.env.MAINNET_URL || "",
      accounts: [
        process.env.PRIVATE_KEY || "",
        process.env.TEST_WALLET_PRIVATE_KEY || "",
      ],
      gas: 2100000,
      gasPrice: 8000000000,
    },
    mumbai: {
      url: process.env.MUMBAINET_URL,
      accounts: [
        process.env.PRIVATE_KEY || "",
        process.env.TEST_WALLET_PRIVATE_KEY || "",
      ],
      gas: 2100000,
      gasPrice: 8000000000
    },
    goerli: {
      url: process.env.GOERLI_URL,
      accounts: [
        process.env.PRIVATE_KEY || "",
        process.env.TEST_WALLET_PRIVATE_KEY || "",
      ],
      gas: 2100000,
      gasPrice: 8000000000
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  mocha: {
    timeout: 100000000,
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.POLYGONSCAN_API_KEY,
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
};

export default config;
