// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract LnToken is ERC20Permit {
    using Address for address;

    bool public initialized;

    uint8 lnTokenDecimal;

    event SetValidBank(address _bank, bool _isValid);

    constructor(string memory _name, string memory _symbol, uint8 _lnTokenDecimal) ERC20(_name, _symbol) ERC20Permit(_name) {
        lnTokenDecimal = _lnTokenDecimal;
    }

    /**
     * @dev
     * whitelisted banks.
     */
    mapping(address => bool) public banks;

    /**
     * @dev
     * only allow sendToBank() between old and new/current bank.
     * only allow banks address to be a contract.
     */
    modifier onlyValidBanks(address _bank) {
        require(banks[_bank] == true, "not valid bank");
        require(_bank.isContract(), "bank address is not contract");
        _;
    }
    /**
     * @dev
     * Override the decimals.
     */
    function decimals() public view override returns (uint8) {
        return lnTokenDecimal;
    }
    /**
     * @dev
     * Initialize the first valid bank address.
     * Function should only be called a single right after deploy. 
     */
    function initialize(address _bank) public {
        require(initialized == false, "already initialized");
        banks[_bank] = true;
        initialized = true;
    }

    /**
     * @dev
     * set bank address to valid or invalid.
     */
    function setValidBank(address _bank, bool _isValid) external onlyValidBanks(msg.sender) {
        banks[_bank] = _isValid;
        emit SetValidBank(_bank, _isValid);
    }

    /**
     * @dev
     * mint LnToken to a bank.
     */
    function mintToBank(address _to, uint256 _amount) external onlyValidBanks(_to) {
        _mint(_to, _amount);
    }

    /**
     * @dev
     * burn LnToken from a address.
     */
    function burn(uint256 _amount) external onlyValidBanks(msg.sender) {
        _burn(msg.sender, _amount);
    }


    /**
     * @dev
     * A safe way to send LnToken between banks.
     * Ensured the sender or recipient is a owner bank.
     */
    function sendToBank(address _to, uint256 _amount) external onlyValidBanks(msg.sender) onlyValidBanks(_to) {
        IERC20(address(this)).transferFrom(msg.sender, _to, _amount);
    }


}