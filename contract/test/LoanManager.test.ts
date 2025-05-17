import { expect } from "chai";
import { ethers } from "hardhat";
import { MockERC20, MockPriceFeed, LoanManager } from "../typechain-types"; // adjust to your path


describe("LoanManager", function () {
  let cusd: MockERC20;
  let priceFeed: MockPriceFeed;
  let loanManager: LoanManager;
  let owner: any;
  let borrower: any;
  let lender: any;

  beforeEach(async function () {
    [owner, borrower, lender] = await ethers.getSigners();

    // Deploy mock cUSD
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    cusd = await MockERC20.deploy("cUSD", "cUSD");
    cusd.waitForDeployment()

    // Mint cUSD to lender and borrower
    await cusd.mint(lender.address, ethers.parseEther("100000"));
    await cusd.mint(borrower.address, ethers.parseEther("10000"));

    // Deploy mock Chainlink price feed
    const MockPriceFeed = await ethers.getContractFactory("MockPriceFeed");
    priceFeed = await MockPriceFeed.deploy(ethers.parseUnits("1", 8), 8); // $1.00 CELO
    await priceFeed.waitForDeployment();

    // Deploy the LoanManager
    const LoanManager = await ethers.getContractFactory("LoanManager");
    loanManager = await LoanManager.deploy(cusd.getAddress(), priceFeed.getAddress());
    await loanManager.waitForDeployment();
  });

  it("should allow a borrower to request a loan with CELO collateral", async () => {
    const loanAmount = ethers.parseEther("1000"); // 1000 cUSD
    const celoCollateral = ethers.parseEther("1200"); // At 120% collateral ratio

    await loanManager.connect(borrower).requestLoan(
      loanAmount,
      10, // max interest rate
      60 * 60 * 24 * 30, // 30 days
      { value: celoCollateral }
    );

    const requests = await loanManager.getAllLoanRequests();
    expect(requests.length).to.equal(1);
    expect(requests[0].borrower).to.equal(borrower.address);
  });

  it("should allow a lender to fund a loan", async () => {
    const loanAmount = ethers.parseEther("1000");
    const celoCollateral = ethers.parseEther("1200");

    await loanManager.connect(borrower).requestLoan(
      loanAmount,
      10,
      60 * 60 * 24 * 30,
      { value: celoCollateral }
    );

    await cusd.connect(lender).approve(loanManager.getAddress(), loanAmount);

    await loanManager.connect(lender).fundLoan(1);

    const lenderLoans = await loanManager.getLenderLoans(lender);
    expect(lenderLoans.length).to.equal(1);
  });

  it("should repay a loan and return CELO to borrower", async () => {
    const loanAmount = ethers.parseEther("1000");
    const celoCollateral = ethers.parseEther("1200");

    await loanManager.connect(borrower).requestLoan(
      loanAmount,
      10,
      60 * 60 * 24 * 30,
      { value: celoCollateral }
    );

    await cusd.connect(lender).approve(loanManager.getAddress(), loanAmount);
    await loanManager.connect(lender).fundLoan(1);

    const repayment = ethers.parseEther("1100");
    await cusd.connect(borrower).approve(loanManager.getAddress(), repayment);

    // Fast-forward time by 31 days to accrue interest
    await ethers.provider.send("evm_increaseTime", [60 * 60 * 24 * 31]);
    await ethers.provider.send("evm_mine", []);

    await loanManager.connect(borrower).repayLoanWithReward(1);

    const status = await loanManager.loansStatus(1);
    expect(status.repaid).to.equal(true);
  });

  it("should allow liquidation if collateral value drops below threshold", async () => {
    const loanAmount = ethers.parseEther("1000");
    const celoCollateral = ethers.parseEther("1200");

    await loanManager.connect(borrower).requestLoan(
      loanAmount,
      10,
      60 * 60 * 24 * 30,
      { value: celoCollateral }
    );

    await cusd.connect(lender).approve(loanManager.getAddress(), loanAmount);
    await loanManager.connect(lender).fundLoan(1);

    // Fast-forward time past loan due date
    await ethers.provider.send("evm_increaseTime", [60 * 60 * 24 * 31]);
    await ethers.provider.send("evm_mine", []);

    // Drop CELO price to $0.80
    await priceFeed.setPrice(ethers.parseUnits("0.80", 8));

    await loanManager.connect(owner).liquidateLoan(1);

    const status = await loanManager.loansStatus(1);
    expect(status.defaulted).to.equal(true);
  });
});
