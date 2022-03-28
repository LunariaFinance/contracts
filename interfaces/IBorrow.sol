// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "interfaces/IVault.sol";


interface IBorrow {
    function borrow(
        uint256 _amount, 
        uint256 _hostageAmt,
        uint256 _hostageBalance, 
        address _vault, 
        uint256 _existingDebt
        ) external view returns (uint256 newBorrowedAmount, uint256 newHostageAmt, uint256 newBorrowTime);

        function repay(
        uint256 _amount, 
        uint256 _existingDebt
        ) external view returns (uint256 borrowedAmount, uint256 borrowTime);

        function wtithdraw(
        uint256 _withdrawAmount,
        address _vault,
        uint256 _hostageBalance,
        uint256 _existingDebt
    ) external view returns (uint256 newHostageBalance, uint256 newBorrowTime);

    function calculateLTV(
        uint256 _amount, 
        uint256 _existingDebt, 
        uint256 _hostageAmt, 
        uint256 _hostageBalance, 
        IVault _ibToken
        ) external view returns (uint256);
}

