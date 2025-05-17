

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const cusdAddress = "0x874069fa1eb16d44d622f2e0ca25eea172369bc1"
const cusdCeloPrice = "0x022F9dCC73C5Fb43F2b4eF2EF9ad3eDD1D853946"

const LoanManagerModule = buildModule("loanManagerModule", (m) => {


  const loanManager = m.contract("LoanManager", [cusdAddress, cusdCeloPrice])

  return { loanManager };
});

export default LoanManagerModule;
