import { createAppKit } from "@reown/appkit/react";
import { EthersAdapter } from "@reown/appkit-adapter-ethers";
import { defineChain } from "@reown/appkit/networks";

// Your project ID from environment variable
const projectId = import.meta.env.VITE_APPKIT_PROJECT_ID;

console.log({ projectId });

// Define Celo Alfajores L2 testnet
const celoAlfajores = defineChain({
  id: 44787,
  caipNetworkId: "eip155:44787",
  chainNamespace: "eip155",
  name: "Celo Alfajores L2 Testnet",
  nativeCurrency: {
    decimals: 18,
    name: "Celo",
    symbol: "CELO",
  },
  rpcUrls: {
    default: {
      http: [import.meta.env.VITE_ALFAJORES_RPC_URL || "https://alfajores-forno.celo-testnet.org"],
    },
  },
  blockExplorers: {
    default: {
      name: "Celo Explorer",
      url: "https://alfajores.celoscan.io",
    },
  },
  contracts: {
    cUSD: {
      address: "0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1",
      abi: [], // Add cUSD ABI if needed
    },
    lumenVault: {
      address: import.meta.env.VITE_LUMEN_VAULT_CONTRACT_ADDRESS,
      abi: [], // Add LumenVault contract ABI if needed
    },
  },
});

// Set the networks
const networks = [celoAlfajores];

// Create a metadata object - optional
const metadata = {
  name: "Lumenvault",
  description: "Decentralized micro-loan",
  url: "https://lumenvault.vercel.app",
  icons: ["https://avatars.mywebsite.com/"],
};

// Create a AppKit instance
createAppKit({
  adapters: [new EthersAdapter()],
  networks,
  metadata,
  projectId,
  features: {
    analytics: true,
  },
});