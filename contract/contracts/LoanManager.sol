// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./interfaces/ILoanManager.sol";
import "./libraries/CollateralUtils.sol";
import "./libraries/LoanCalculator.sol";
import "./storage/LoanStorage.sol";

contract LoanManager is ILoanManager, LoanStorage, ReentrancyGuard, Pausable {
    using CollateralUtils for uint256;
    using Address for address payable;

    IERC20 public cusd;
    AggregatorV3Interface public priceFeed; // CELO price feed
    address public owner;

    uint256 public collateralizationRatio = 120;
    uint256 public liquidationThreshold = 110; // 110%
    uint256 public loanCounter;
    uint256 public minLoanAmount = 10 ** 18;
    uint256 public maxLoanAmount = 100_000 * 10 ** 18;
    uint256 public constant LIQUIDATOR_REWARD_PERCENT = 5; // 5% of collateral

    constructor(IERC20 _cusd, AggregatorV3Interface _priceFeed) {
        cusd = _cusd;
        priceFeed = _priceFeed;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    function requestLoan(
        uint256 amount,
        uint256 maxInterestRate,
        uint256 duration
    ) external payable override whenNotPaused nonReentrant {
        require(
            amount >= minLoanAmount && amount <= maxLoanAmount,
            "Invalid loan amount"
        );

        uint256 celoPrice = getCELOPrice();

        uint256 requiredCollateral = amount.calculateRequiredCollateral(
            celoPrice,
            collateralizationRatio,
            priceFeed.decimals()
        );

        require(msg.value >= requiredCollateral, "Insufficient collateral");

        loanCounter++;
        


        LoanRequest storage request = loanRequests[loanCounter];
        request.amount = amount;
        request.maxInterestRate = maxInterestRate;
        request.duration = duration;
        request.dueDate = block.timestamp + duration;

        loansCore[loanCounter] = LoanCore({
            borrower: msg.sender,
            lender: address(0),
            amount: amount,
            collateral: msg.value,
            interestRate: maxInterestRate,
            rateType: InterestRateType.FIXED,
            duration: duration
        });

        borrowerLoans[msg.sender].push(loanCounter);

        emit LoanRequested(
            loanCounter,
            msg.sender,
            amount,
            msg.value,
            maxInterestRate,
            duration
        );
    }

    function fundLoan(
        uint256 loanId
    ) external override whenNotPaused nonReentrant {
        LoanCore storage loan = loansCore[loanId];
        LoanStatus storage status = loansStatus[loanId];

        require(!status.active, "Loan already active");
        require(loan.lender == address(0), "Loan already funded");
        require(
            cusd.allowance(msg.sender, address(this)) >= loan.amount,
            "Insufficient allowance for this user"
        );

        require(
            cusd.transferFrom(msg.sender, address(this), loan.amount),
            "Transfer failed"
        );

        loan.lender = msg.sender;
        status.startTime = block.timestamp;
        status.active = true;

        require(
            cusd.transfer(loan.borrower, loan.amount),
            "Loan disbursement failed"
        );

        lenderLoans[msg.sender].push(loanId);
        borrowerLoans[loan.borrower].push(loanId);

        emit LoanFunded(loanId, msg.sender);
        emit LoanDisbursed(loanId, loan.borrower, loan.amount);
    }

    function allowanceCaller() external view returns (uint256) {
        uint256 allowance = cusd.allowance(msg.sender, address(this));
        return allowance;
    }

    function accrueInterest(uint256 loanId) internal {
        LoanCore storage loan = loansCore[loanId];
        LoanInterest storage interest = loansInterest[loanId];
        LoanStatus storage status = loansStatus[loanId];

        require(status.active, "Loan not active");

        uint256 timeElapsed;
        if (interest.lastInterestAccrualTimestamp == 0) {
            timeElapsed = loan.duration;
        } else {
            timeElapsed =
                block.timestamp -
                interest.lastInterestAccrualTimestamp;
        }

        require(timeElapsed > 0, "No time elapsed for interest accrual");

        uint256 accrued = LoanCalculator.calculatePeriodicInterest(
            loan.amount,
            loan.interestRate,
            timeElapsed
        );

        interest.accruedInterest += accrued;
        interest.lastInterestAccrualTimestamp = block.timestamp;

        emit InterestAccrued(loanId, accrued);
    }

    /// @notice Fully repays a loan, including principal and accrued interest, with a reward retained by the contract
    /// @param loanId The ID of the loan to repay
    function repayLoanWithReward(
        uint256 loanId
    ) external override whenNotPaused nonReentrant {
        LoanCore storage loan = loansCore[loanId];
        LoanStatus storage status = loansStatus[loanId];
        LoanInterest storage interest = loansInterest[loanId];

        require(status.active, "Loan not active");
        require(msg.sender == loan.borrower, "Not borrower");

        accrueInterest(loanId);

        uint256 totalInterest = interest.accruedInterest;
        require(totalInterest > 0, "No interest accrued");

        uint256 reward = (totalInterest * 20) / 100;
        uint256 lenderInterest = totalInterest - reward;

        interest.lastInterestAccrualTimestamp = block.timestamp;

        uint256 totalRepayment = loan.amount + totalInterest;

        require(totalRepayment > loan.amount, "Interest not calculated");
        require(reward > 0, "No reward calculated");

        require(
            cusd.transferFrom(msg.sender, address(this), totalRepayment),
            "Transfer failed"
        );

        uint256 amountToLender = loan.amount + lenderInterest;
        require(
            cusd.transfer(loan.lender, amountToLender),
            "Transfer to lender failed"
        );

        status.active = false;
        status.repaid = true;
        status.defaulted = false;

        returnCollateral(loanId);

        emit LoanRepaid(loanId, msg.sender, totalRepayment);
        emit RewardCollected(loanId, reward);
    }

    /// @notice Liquidates a loan that is both overdue and has CELO collateral value below the liquidation threshold
    /// @param loanId The ID of the loan to liquidate
    function liquidateLoan(
        uint256 loanId
    ) external override whenNotPaused nonReentrant {
        LoanCore storage loan = loansCore[loanId];
        LoanStatus storage status = loansStatus[loanId];

        require(status.active, "Loan not active");
        require(!status.repaid, "Loan already repaid");
        require(
            block.timestamp > status.startTime + loan.duration,
            "Loan not overdue"
        );

        uint256 celoPrice = getCELOPrice();
        uint256 collateralValue = (loan.collateral * celoPrice) /
            (10 ** priceFeed.decimals());
        uint256 requiredCollateralValue = (loan.amount * liquidationThreshold) /
            100;

        require(
            collateralValue < requiredCollateralValue,
            "Collateral above liquidation threshold"
        );

        transferCollateralToLender(loanId);

        status.active = false;
        status.defaulted = true;

        emit LoanLiquidated(loanId, loan.lender, loan.amount);
    }

    /// @notice Transfers CELO collateral, splitting 5% to the liquidator and 95% to the lender
    /// @param loanId The ID of the loan
    function transferCollateralToLender(uint256 loanId) internal {
        LoanCore storage loan = loansCore[loanId];

        require(
            address(this).balance >= loan.collateral,
            "Insufficient collateral balance"
        );

        uint256 amount = loan.collateral;
        uint256 liquidatorReward = (amount * LIQUIDATOR_REWARD_PERCENT) / 100;
        uint256 lenderAmount = amount - liquidatorReward;

        loan.collateral = 0; // Prevent reentrancy

        if (liquidatorReward > 0) {
            payable(msg.sender).sendValue(liquidatorReward);
        }
        if (lenderAmount > 0) {
            payable(loan.lender).sendValue(lenderAmount);
        }
    }

    /// @notice Returns the CELO collateral to the borrower when the loan is repaid
    /// @param loanId The ID of the loan
    function returnCollateral(uint256 loanId) internal {
        LoanCore storage loan = loansCore[loanId];
        uint256 amount = loan.collateral;

        if (amount > 0) {
            loan.collateral = 0;
            payable(loan.borrower).sendValue(amount);
        }
    }

    /// @notice Retrieves the latest CELO/USD price from the Chainlink price feed
    /// @return The CELO price in USD (adjusted for decimals)
    function getCELOPrice() public view returns (uint256) {
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        require(answeredInRound >= roundId, "Stale price");
        require(updatedAt >= block.timestamp - 1 hours, "Price too old");
        return uint256(price);
    }

    function withdrawRewards(address _owner) external onlyOwner nonReentrant {
        uint256 contractBalance = cusd.balanceOf(address(this));
        require(contractBalance > 0, "No rewards to withdraw");

        require(
            cusd.transfer(_owner, contractBalance),
            "Reward withdrawal failed"
        );

        emit RewardsWithdrawn(_owner, contractBalance);
    }

    function getRequiredCollateralAmount(
        uint256 loanAmount
    ) external view returns (uint256) {
        uint256 celoPrice = getCELOPrice();
        return
            loanAmount.calculateRequiredCollateral(
                celoPrice,
                collateralizationRatio,
                priceFeed.decimals()
            );
    }

    function updateCollateralizationRatio(uint256 newRatio) external onlyOwner {
        require(newRatio >= 100, "Ratio too low");
        collateralizationRatio = newRatio;
    }

    function updateLiquidationThreshold(
        uint256 newThreshold
    ) external onlyOwner {
        require(newThreshold >= 100, "Threshold too low");
        liquidationThreshold = newThreshold;
    }

    function setLoanLimits(
        uint256 _minLoanAmount,
        uint256 _maxLoanAmount
    ) external onlyOwner {
        require(
            _minLoanAmount > 0,
            "Minimum loan amount must be greater than 0"
        );
        require(
            _maxLoanAmount > _minLoanAmount,
            "Maximum loan amount must be greater than minimum loan amount"
        );
        minLoanAmount = _minLoanAmount;
        maxLoanAmount = _maxLoanAmount;
    }

    function getBorrowerLoans(
        address borrower
    ) external view returns (uint256[] memory) {
        return borrowerLoans[borrower];
    }

    function getLenderLoans(
        address lender
    ) external view returns (uint256[] memory) {
        return lenderLoans[lender];
    }

    function getTotalLoanPayment(
        uint256 loanId
    )
        external
        view
        returns (
            uint256 totalPayment,
            uint256 principal,
            uint256 interestAmount
        )
    {
        LoanCore storage loan = loansCore[loanId];
        LoanStatus storage status = loansStatus[loanId];
        LoanInterest storage interest = loansInterest[loanId];

        require(loan.amount > 0, "Loan does not exist");

        principal = loan.amount;

        if (!status.active && status.repaid) {
            return (
                principal + interest.accruedInterest,
                principal,
                interest.accruedInterest
            );
        }

        uint256 timeElapsed;
        if (status.active) {
            if (interest.lastInterestAccrualTimestamp == 0) {
                timeElapsed = block.timestamp - status.startTime;
            } else {
                timeElapsed =
                    block.timestamp -
                    interest.lastInterestAccrualTimestamp;
            }

            uint256 additionalInterest = LoanCalculator
                .calculatePeriodicInterest(
                    loan.amount,
                    loan.interestRate,
                    timeElapsed
                );

            interestAmount = interest.accruedInterest + additionalInterest;
        } else {
            interestAmount = interest.accruedInterest;
        }

        totalPayment = principal + interestAmount;

        return (totalPayment, principal, interestAmount);
    }

    function getAllLoanRequests()
        external
        view
        returns (LoanRequestDetail[] memory)
    {
        uint256 validCount = 0;
        for (uint256 i = 1; i <= loanCounter; i++) {
            LoanRequest memory request = loanRequests[i];
            if (request.amount > 0) {
                validCount++;
            }
        }

        LoanRequestDetail[] memory details = new LoanRequestDetail[](
            validCount
        );
        uint256 currentIndex = 0;

        for (uint256 i = 1; i <= loanCounter; i++) {
            LoanRequest memory request = loanRequests[i];
            LoanStatus memory status = loansStatus[i];
            LoanCore memory core = loansCore[i];

            if (request.amount > 0) {
                details[currentIndex] = LoanRequestDetail({
                    loanId: i,
                    borrower: core.borrower,
                    amount: request.amount,
                    maxInterestRate: request.maxInterestRate,
                    dueDate: request.dueDate,
                    duration: request.duration,
                    collateralAmount: core.collateral,
                    isActive: status.active,
                    hasRepaid: status.repaid
                });
                currentIndex++;
            }
        }

        return details;
    }
}
