// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILoanManager {
    enum InterestRateType { FIXED, VARIABLE }

    // Events
    event LoanRequested(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 amount,
        uint256 collateral,
        uint256 maxInterestRate,
        uint256 duration
    );
    event LoanFunded(uint256 indexed loanId, address indexed lender);
    event LoanRepaid(uint256 indexed loanId, address indexed borrower, uint256 amount);
    event InterestAccrued(uint256 indexed loanId, uint256 amount);
    event LoanDisbursed(uint256 indexed loanId, address indexed borrower, uint256 amount);
    event RewardCollected(uint256 indexed loanId, uint256 amount);
    event LoanLiquidated(uint256 indexed loanId, address indexed lender, uint256 amount);
    event RewardsWithdrawn(address indexed owner, uint256 amount);

    // Functions
    function requestLoan(
        uint256 amount,
        uint256 maxInterestRate,
        uint256 duration
    ) external payable;

    function fundLoan(uint256 loanId) external;

    function repayLoanWithReward(uint256 loanId) external;

    function liquidateLoan(uint256 loanId) external;
}