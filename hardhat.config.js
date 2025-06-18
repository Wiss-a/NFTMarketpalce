/** @type import('hardhat/config').HardhatUserConfig */
// require("@nomiclabs/hardhat-ethers");

// module.exports = {
//   solidity: "0.8.28",
//   networks: {
//     localhost: {
//       url: "http://127.0.0.1:8545",  
//       accounts: ["my_Metamask_key"]
//     }
//   }
// };

require("@nomiclabs/hardhat-waffle");
require("dotenv").config();

module.exports = {
  solidity: "0.8.28",
  settings: {
      optimizer: {
        enabled: true,
        runs: 1  // Try lower like 100 or 50 for smaller contract size
      },
    },
  networks: {
    sepolia: {
      url: `https://eth-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
      accounts: [process.env.PRIVATE_KEY]
    },
  },
  
    contractSizer: {
    runOnCompile: true,
    strict: true
  }
};
