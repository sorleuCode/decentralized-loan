import { HardhatUserConfig, vars  } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";





const config: HardhatUserConfig = {
  solidity: "0.8.24",
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },

  networks: {
    alfajores: {
      // can be replaced with the RPC url of your choice.
      url: "https://alfajores-forno.celo-testnet.org",
      accounts: vars.has("PRIVATE_KEY") ? [vars.get("PRIVATE_KEY")] : [],
  },

  },
  
  etherscan: {
    apiKey: vars.get("CELOSCAN_API_KAEY"),
     customChains: [
      {
          network: "alfajores",
          chainId: 44787,
          urls: {
              apiURL: "https://api-alfajores.celoscan.io/api",
              browserURL: "https://alfajores.celoscan.io",
          },
      },
      {
          network: "celo",
          chainId: 42220,
          urls: {
              apiURL: "https://api.celoscan.io/api",
              browserURL: "https://celoscan.io/",
          },
      },
  ]
},
};


export default config;
