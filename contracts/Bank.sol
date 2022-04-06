// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "interfaces/IBorrow.sol";
import "interfaces/ILnToken.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "interfaces/IVault.sol";


/**
 * @dev
 * Bank contract will mint LnUSD for Vault to borrow.
 * Bank contract will keep track of Vault's debt.
 * When Vault repay LnUSD, Bank will calculate the interest owed.
 *
 * Only 1 valid bank exist at anytime for a lnToken. 
 * Can have many vaults and many strats. But only 1 bank.
 */
contract Bank is ReentrancyGuard, Ownable {

    using SafeMath for uint256;

    string public bankName;
    ILnToken public lnToken;
    IBorrow public borrowImpl;
    IVault public vault;

    bool public initialized;

    uint256 public borrowFee; // 5/1000 = 0.005 aka 0.5%
    address public treasury;

    uint256 constant public MAX_BORROW_FEE = 100;

    struct BorrowCandidate {
        address implementation;
        uint proposedTime;
    }

    // The last proposed strategy to switch to.
    BorrowCandidate public borrowCandidate;
    // The minimum time it has to pass before a strat candidate can be approved.
    uint256 public immutable approvalDelay;

    

    /**
     * @dev
     * struct to track user debt and interest 
     */
    struct BorrowerInfo {
        uint256 borrowedAmount;
        uint256 borrowTime;
        uint256 collateralAmount;
    }
    /** 
     * @dev
     * mapping to track borrower infos
     */
    mapping (address => BorrowerInfo) public borrowerInfoMap;

    event BankTransfer(address _from, address _to, uint256 _amount);
    event Repaid(address indexed _borrower, uint256 _amount, address indexed _vault);
    event Borrowed(address indexed _borrower, uint256 _collateralAmt, uint256 _amount, address indexed _vault);
    event Withdrawn(address indexed _borrower, uint256 _withdrawAmount, address indexed _vault);
    event NewBorrowCandidate(address _implementation);
    event UpgradeBorrowImpl(address _implementation);

    /** 
     * @param _bankName name of the bank eg: 'WFTM SCREAM BANK'
     * @param _approvalDelay time before new borrow implementation can be upgraded.
     * @param _treasury address where borrowFee goes.
     */
    constructor(
        string memory _bankName,
        uint256 _approvalDelay,
        address _treasury
        ) {
        bankName = _bankName;
        approvalDelay = _approvalDelay;
        treasury = _treasury;
        borrowFee = 5;
    }

    /**
     * @dev
     * Initialize the borrowable token and the borrow implementation.
     * This function should only be called a single time only right after deploying.
     * @param _lnToken address of lnToken this bank suppose to mint.
     * @param _borrowImpl address of borrow implementation contract.
     * @param _vault address of vault that can borrow with this bank.
     */
    function initialize(ILnToken _lnToken, IBorrow _borrowImpl, IVault _vault) public onlyOwner {
        require(initialized == false, "already initialized");
        lnToken = _lnToken;
        borrowImpl = _borrowImpl;
        vault = _vault;
        initialized = true;
    }
    /** 
     * @dev Sets the candidate for the new borrow to use with this bank.
     * @param _implementation The address of the candidate borrow.  
     */
    function proposeBorrowImpl(address _implementation) public onlyOwner {
        borrowCandidate = BorrowCandidate({
            implementation: _implementation,
            proposedTime: block.timestamp
         });

        emit NewBorrowCandidate(_implementation);
    }
    /** 
     * @dev It switches the active strat for the strat candidate. After upgrading, the 
     * candidate implementation is set to the 0x00 address, and proposedTime to a time 
     * happening in +100 years for safety. 
     */
    function upgradeBorrowImpl() public onlyOwner {
        require(borrowCandidate.implementation != address(0), "There is no candidate");
        require(borrowCandidate.proposedTime.add(approvalDelay) < block.timestamp, "Delay has not passed");

        emit UpgradeBorrowImpl(borrowCandidate.implementation);

        borrowImpl = IBorrow(borrowCandidate.implementation);
        borrowCandidate.implementation = address(0);
        borrowCandidate.proposedTime = 5000000000;
    }

    /// LnToken functions ///
    
    /**
     * @dev
     * mint lnToken to this address 
     * @param _amount the amount of lnToken to mint.
     */
    function mintLnToken(uint256 _amount) public onlyOwner {
        lnToken.mintToBank(address(this), _amount);
    }

    /** 
     * @dev
     * change the owner bank of lnToken. 
     * @param _newBank address of a new bank.
     * @param _valid boolean.
     */
    function setValidBank(address _newBank, bool _valid) public onlyOwner {
        lnToken.setValidBank(_newBank, _valid);
    }

    /**
     * @dev
     * get total supply of lnToken. 
     */
    function lnTokenTotalSupply() public view returns (uint256) {
        return lnToken.totalSupply();
    }

    /**
     * @dev
     * return bank balance of lnToken 
     */
    function bankBalance() public view returns (uint256) {
        return lnToken.balanceOf(address(this));
    }

    /**
     * @dev
     * burn lnToken from bank address 
     */
    function burnLnToken(uint256 _amount) public onlyOwner {
        lnToken.burn(_amount);

    }

    /**
     * @dev
     * transfer lnToken to another address 
     */
    function bankTransfer(address _to, uint256 _amount) public onlyOwner {
        lnToken.approve(address(lnToken), _amount);
        lnToken.sendToBank(_to, _amount);
        emit BankTransfer(address(this), _to, _amount);
    }

    /**
     * @dev
     * To get the user's last borrow time and borrowed amount and collateral.
     * @param _borrower address of borrower.
     */
    function getBorrowerInfo(address _borrower) public view returns (uint256, uint256, uint256) {
        uint256 totalDebt = getDebtWithInterest(_borrower);
        return (totalDebt, borrowerInfoMap[_borrower].borrowTime,
            borrowerInfoMap[_borrower].collateralAmount);
        
    }
   
    /**
     * @dev To borrow lnToken.
     * @param _amount amount of lnToken to borrow.
     * @param _collateralAmt amount of collateral to deposit.
     */
    function borrow(
        uint256 _amount, 
        uint256 _collateralAmt
        ) public nonReentrant {

        // user info
        ( , uint256 lastBorrowTime, uint256 collateralBalance) = getBorrowerInfo(msg.sender);

        uint256 existingDebt = getDebtWithInterest(msg.sender);

        (uint256 newBorrowedAmount, uint256 newCollateralAmt, uint256 newBorrowTime) = borrowImpl.borrow(
            _amount, _collateralAmt, collateralBalance, address(vault), existingDebt);

        /** 
         * Make sure that borrowed amount is more equal than the the one in state.
         * Make sure that borrow time is ahead of previous borrow time.
         * Make sure the the borrow amount is more equal than the current borrowed amount in the state. 
         */ 
        require(newBorrowTime > lastBorrowTime, "borrow: new borrow time less than old one.");
        require(newCollateralAmt >= collateralBalance, "borrow: new collateral less than old one.");
        require(newBorrowedAmount >= existingDebt, "borrow: new borrow is less than new one.");
        
        // update user info
        BorrowerInfo memory borrowerInfo;
        borrowerInfo.borrowedAmount = newBorrowedAmount;
        borrowerInfo.borrowTime = newBorrowTime;
        borrowerInfo.collateralAmount = newCollateralAmt;

        borrowerInfoMap[msg.sender] = borrowerInfo;

        // Charge fees from borrowing.
        uint256 borrowableAmt = chargeFee(_amount);

        vault.transferFrom(msg.sender, address(this), _collateralAmt);
        lnToken.transfer(msg.sender, borrowableAmt);
        
        emit Borrowed(msg.sender, _collateralAmt, _amount, address(vault));

    }

    /**
     * @dev to charge borrowFee.
     * @param _borrowAmt the amount to borrow.
     */
    function chargeFee(uint256 _borrowAmt) internal returns (uint256 borrowableAmt) {
        uint256 fee = _borrowAmt.mul(borrowFee).div(1000);
        lnToken.transfer(treasury, fee);
        borrowableAmt = _borrowAmt.sub(fee);
    }

    /**
     * @dev set borrow fee.
     * @param _borrowFee fee. 
     */
    function setBorrowFee(uint256 _borrowFee) public onlyOwner {
        require(_borrowFee < MAX_BORROW_FEE, "setborrowFee: over MAX_BORROW_FEE");
        borrowFee = _borrowFee;
    }

    /**
     * @dev get interest on the borrowed lnTokens.
     * @param _interestRate interest rate in % from vault.
     * @param _borrowedAmount amount of borred lnToken from bank.
     * @param _borrowTime time of last borrow.
     */
    function calculateInterest(
        uint256 _interestRate, 
        uint256 _borrowedAmount, 
        uint256 _borrowTime
        ) view internal returns (uint256) {
        
        //formula for interest = interstRate/365days * (now-borrowTime) * borrowedAmount.
         
        uint256 timeDiff = block.timestamp.sub(_borrowTime).mul(1e18).div(365 days);
        uint256 interest = timeDiff.mul(_interestRate).div(1000);
        return interest.mul(_borrowedAmount).div(1e18);
    }

    /**
     * @dev
     * Helper function to calculate current debt + interest accured. 
     * @param _borrower address of borrower.
     */
    function getDebtWithInterest(
        address _borrower
        ) view public returns (uint256){
            uint256 interestRate = vault.getInterestRate();
            uint256 interestAmt = calculateInterest(interestRate, borrowerInfoMap[_borrower].borrowedAmount,
             borrowerInfoMap[_borrower].borrowTime);
            return borrowerInfoMap[_borrower].borrowedAmount.add(interestAmt);

        }


    /**
     * @dev
     * To repay debt.
     * @param _amount amount of lnToken to repay.
     */
    function repay(
        uint256 _amount
        ) public nonReentrant {

        // user info
        ( , uint256 lastBorrowTime, uint256 collateralAmount) = getBorrowerInfo(msg.sender);

        uint256 existingDebt = getDebtWithInterest(msg.sender);

        (uint256 newBorrowedAmount, uint256 newBorrowTime) = borrowImpl.repay(_amount, existingDebt);

        /**
         * Make sure that borrow amount is less than existing borrow amount in state. 
         * Make sure that borrow time is ahead of the previous time in state.
         */
        require(newBorrowedAmount < existingDebt, "repay: new borrow more than equal to old one.");
        require(newBorrowTime > lastBorrowTime, "repay: new borrow time lesser than old one");

        // update user info
        BorrowerInfo memory borrowerInfo;
        borrowerInfo.borrowedAmount = newBorrowedAmount;
        borrowerInfo.borrowTime = newBorrowTime;
        borrowerInfo.collateralAmount = collateralAmount;

        borrowerInfoMap[msg.sender] = borrowerInfo;

        lnToken.transferFrom(msg.sender, address(this), _amount);


        emit Repaid(msg.sender, _amount, address(vault));
    }

    /**
     * @dev
     * Repay all debt 
     */
    function repayAll() public {
            uint256 debtWithInterest = getDebtWithInterest(msg.sender);
            repay(debtWithInterest);
        }

    /**
     * @dev
     * To withdraw ibTokens.
     * @param _withdrawAmount amount of collateral to withdraw.
     */
    function withdraw(
        uint256 _withdrawAmount
        ) public nonReentrant {

        // user info
        ( , uint256 lastBorrowTime, uint256 collateralBalance) = getBorrowerInfo(msg.sender);
        
        uint256 existingDebt = getDebtWithInterest(msg.sender);
        (uint256 newCollateralAmt, uint256 newBorrowTime) = borrowImpl.wtithdraw(_withdrawAmount, address(vault),
         collateralBalance, existingDebt);

        /**
         * Make sure that borrow time ahead of the previous borrow time in state.
         * Make sure that collateral amount is less equal than the previous collateral amount in state.
         */
        require(newBorrowTime > lastBorrowTime, "withdraw: new borrow time less than old one.");
        require(newCollateralAmt <= collateralBalance, "withdraw: new collateral more than old one.");
        
        // update user info
        BorrowerInfo memory borrowerInfo;
        borrowerInfo.borrowedAmount = existingDebt;
        borrowerInfo.borrowTime = newBorrowTime;
        borrowerInfo.collateralAmount = newCollateralAmt;

        borrowerInfoMap[msg.sender] = borrowerInfo;

        vault.transfer(msg.sender, _withdrawAmount);
        
        emit Withdrawn(msg.sender, _withdrawAmount, address(vault));
        }

    /**
     * @dev
     * To withdraw max collateral fron bank without going below LTV. */
    function withdrawAll() public {

        // user info
        (uint256 newBorrowedAmount, , uint256 collateralBalance)= getBorrowerInfo(msg.sender);

        uint256 lTV = vault.getLTV();
        uint256 maxLtv = lTV.mul(1e18).div(100);
        uint256 minUnderlyingAsset = newBorrowedAmount.mul(1e18).div(maxLtv);
        uint256 pricePerShare = vault.getPricePerFullShare();
        uint256 minCollateral = minUnderlyingAsset.mul(1e18).div(pricePerShare);

        uint256 maxWithdrawable = collateralBalance.sub(minCollateral);

        // give some space to prevent going over ltv slightly.
        withdraw(maxWithdrawable.mul(999).div(1000));     
    }

}