import { createAppKit } from "@reown/appkit/react";
import { EthersAdapter } from "@reown/appkit-adapter-ethers";
import { defineChain } from "@reown/appkit/networks";

// Your project ID from environment variable
const projectId = import.meta.env.VITE_APPKIT_PROJECT_ID;

console.log({ projectId });
const pharosDevnet = defineChain({
  id: 50002,
  caipNetworkId: "eip155:50002",
  chainNamespace: "eip155",
  name: "Pharos Devnet",
  nativeCurrency: {
    decimals: 18,
    name: "Pharos Test Token",
    symbol: "PTT",
  },
  rpcUrls: {
    default: {
      http: ["https://devnet.dplabs-internal.com/"],
    },
  },
  blockExplorers: {
    default: {
      name: "Pharos Scan",
      url: "https://pharosscan.xyz/",
    },
  },
  contracts: {
    // Add the contracts here
  },
});
// 2. Set the networks
const networks = [pharosDevnet];

// 3. Create a metadata object - optional
const metadata = {
  name: "Lumenvault",
  description: "Decentralized micro-loan",
  url: "https://lumenvault.vercel.app", 
  icons: ["https://avatars.mywebsite.com/"],
};

// 4. Create a AppKit instance
createAppKit({
  adapters: [new EthersAdapter()],
  networks,
  metadata,
  projectId,
  features: {
    analytics: true, 
  },
});