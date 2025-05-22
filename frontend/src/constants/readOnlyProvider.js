import { JsonRpcProvider } from "ethers";

export const readOnlyProvider = new JsonRpcProvider(
  import.meta.env.VITE_ALFAJORES_RPC_URL
);
