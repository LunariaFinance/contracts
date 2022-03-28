
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "interfaces/IStrategy.sol";
import "interfaces/ILnToken.sol";


interface IVault is IERC20 {
    function deposit(uint256) external;
    function depositAll() external;
    function withdraw(uint256) external;
    function withdrawAll() external;
    function getPricePerFullShare() external view returns (uint256);
    function upgradeStrat() external;
    function balance() external view returns (uint256);
    function strategy() external view returns (IStrategy);
    function getInterestRate() external view returns (uint256);
    function getLTV() external view returns (uint256);
    function getLnToken() external view returns (ILnToken);
}