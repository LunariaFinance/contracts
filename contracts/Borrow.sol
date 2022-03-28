// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "interfaces/ILnToken.sol";
import "interfaces/IVault.sol";


/**
 * @dev
 * Borrow consist of the methods for user to interact with Bank.
 * Each vault will have its own Borrow.
 * Each Borrow will initialize with different bank and lnToken.
 */
contract Borrow {
    
    using SafeMath for uint256;
    
    /** 
     * @dev the logic bank use for borrow.
     * @param _amount amount of lnToken to borrow. 
     * @param _collateralAmt amount of collateral used to borrow.
     */
    function borrow(
        uint256 _amount, 
        uint256 _collateralAmt,
        uint256 _collateralBalance, 
        address _vault, 
        uint256 _existingDebt
        ) 
        external view returns (uint256 newBorrowedAmount, uint256 newCollateralAmt, uint256 newBorrowTime) {

        IVault ibToken = IVault(_vault);

        ILnToken lnToken = ibToken.getLnToken();

        require(calculateLTV(_amount, _existingDebt, _collateralAmt, _collateralBalance, ibToken) <= ibToken.getLTV().mul(1e18).div(100), 
            "_borrow: over LTV");
        
        require(lnToken.balanceOf(address(msg.sender)) >= _amount, "_borrow: not enough lnToken in bank");

        newBorrowTime = block.timestamp;
        
        // add the interest and new borrow amount to the exisitng debt. 
        newBorrowedAmount = _existingDebt.add(_amount);
        newCollateralAmt = _collateralBalance.add(_collateralAmt);   

    }

    /**
     * @dev
     * To calculate LTV of a certain borrowing position. 
     * @param _amount the amount of new debt user want to borrow.
     * @param _existingDebt the existint debt user currently has.
     * @param _collateralBalance the amount of collateral user have deposited into bank.
     * @param _ibToken the address of the vault the user want to borrow with.
     */
    function calculateLTV(
        uint256 _amount, 
        uint256 _existingDebt, 
        uint256 _collateralAmt, 
        uint256 _collateralBalance, 
        IVault _ibToken
        ) public view returns (uint256){

        // fomula for getting underlying asset amount is pricePerShare*totalCollateral.
        uint256 debt = _amount.add(_existingDebt);
        uint256 pricePerShare = _ibToken.getPricePerFullShare();

        uint256 collateralTotal = _collateralBalance.add(_collateralAmt);

        uint256 underlyingAsset = pricePerShare.mul(collateralTotal).div(1e18);

        // returns as 1e18 format represent eg: 80.
        return debt.mul(1e18).div(underlyingAsset);

    }

    /**
     * @dev
     * To repay x amount of lnToken to the bank. 
     * @param _amount the amount of lnToken to repay.
     * @param _existingDebt the debt owed.
     */
    function repay(
        uint256 _amount, 
        uint256 _existingDebt
        ) external view returns (uint256 borrowedAmount, uint256 borrowTime) {
            require(_amount <= _existingDebt, "_repay: over repaid");
            borrowedAmount = _existingDebt.sub(_amount);
            borrowTime = block.timestamp;
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
        ) view public returns (uint256) {
        
        //formula for interest = interstRate/365days * (now-borrowTime) * borrowedAmount.
         
        uint256 timeDiff = block.timestamp.sub(_borrowTime).mul(1e18).div(365 days);
        uint256 interest = timeDiff.mul(_interestRate).div(1000);
        return interest.mul(_borrowedAmount).div(1e18);
    }

    /**
     * @dev 
     * To withdraw x amount of ibToken from bank without being over the LTV. 
     * @param _withdrawAmount the amount of collateral to withdraw.
     * @param _vault address of vault.
     * @param _collateralBalance balance of collateral of borrower.
     * @param _existingDebt debt borrower still owes.
     */
    function wtithdraw(
        uint256 _withdrawAmount,
        address _vault,
        uint256 _collateralBalance,
        uint256 _existingDebt
    ) external view returns (uint256 newCollateralBalance, uint256 newBorrowTime) {
        
        IVault ibToken = IVault(_vault);
        uint256 lTV = ibToken.getLTV();

        newCollateralBalance = _collateralBalance.sub(_withdrawAmount);

        uint256 newLtv = calculateLTV(0, _existingDebt, 0, newCollateralBalance, ibToken);

        require(newLtv <= lTV.mul(1e18).div(100), "_withdraw: over LTV");       
        newBorrowTime = block.timestamp; 

    }

}