// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
* @title Feddy (FEDDY)
* @notice Feddy the Based Bear  c(·_·)c 
**/

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

contract Feddy is ERC20, ERC20Permit, Ownable(msg.sender) {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

        
    constructor() ERC20("Feddy", "FEDDY") ERC20Permit("Feddy") {
        _mint(msg.sender, 1000000000000000000000000000);
        burnBlock = block.number + BLOCK_INTERVAL;
    }
     
    EnumerableMap.AddressToUintMap private _addressToBlockNumber;
    EnumerableMap.AddressToUintMap private _addressToBalance;

    uint256 private constant SCALE = 1e18;
    uint256 public constant BLOCK_INTERVAL = 1296000; // Default reward/burn interval is 30 days.
    uint256 public burnBlock;
    uint256 public burnPercent = 2;
    uint256 public rewardPercent = 2;
    bool    public isOwnerTranfersDisabled = false;

    event NewRewardBlock(address indexed addr, uint256 blockNumber);
    event NewRewardBalance(address indexed addr, uint256 amount);
    event TokensRewarded(address indexed addr, uint256 amount);
    event NewBurnBlock(uint256 blockNumber);
    event TokensBurned(address indexed addr, uint256 amount);

    /** 
    *
    * PURPOSE:
    *   - Rewards tokens from Treasury.
    * INFO:
    *   - Each token holder can reward themselves tokens from Treasury every 1296000 blocks (approx. 30 days).
    *   - This function needs to be run by every new token holder to set an initial reward block and balance.
    *   - If an address transfers tokens after executing this function, they will need to re-run to create a new reward balance and block.
    *   - Contract owner cannot collect rewards.
    *
    */     
    function rewardTokens() public {

        require(_msgSender() != owner(), "Sender cannot be contract owner");
        uint256 ownerBalance = balanceOf(owner());
        require(ownerBalance > 0, "Treasury Balance needs to be greater than 0");
        uint256 holderBalance = balanceOf(_msgSender());
        require(holderBalance > 0, "Senders balance needs to be greater than 0");

        if (!isBlockNumberRegistered(_msgSender()) || !isBalanceRegistered(_msgSender())) {
            _addressToBalance.set(_msgSender(),holderBalance);
            _addressToBlockNumber.set(_msgSender(), (block.number + BLOCK_INTERVAL));
        }

        uint256 rewardBalance =  _addressToBalance.get(_msgSender());
        uint256 rewardBlock =  _addressToBlockNumber.get(_msgSender());
       
        if (block.number >= rewardBlock && holderBalance >= rewardBalance) {    
            uint256 totalRewardAmount = (ownerBalance * rewardPercent) / 100;
            uint256 totalSupply = totalSupply();
            uint256 holdersSupply = totalSupply - ownerBalance;
            uint256 holderPercent = divideAndScale(rewardBalance, holdersSupply);
            uint256 transferAmount = (totalRewardAmount * holderPercent) / SCALE;

            _addressToBlockNumber.set(_msgSender(), (block.number + BLOCK_INTERVAL));
            _transfer(owner(), _msgSender(), transferAmount);
            _addressToBalance.set(_msgSender(), balanceOf(_msgSender()));
            
            emit TokensRewarded(_msgSender(), transferAmount);
        }

        emit NewRewardBalance(_msgSender(), _addressToBalance.get(_msgSender()));   
        emit NewRewardBlock(_msgSender(), _addressToBlockNumber.get(_msgSender()));
        
    }

    /** 
    *
    * PURPOSE:
    *   - Burns tokens from Treasury.
    *
    * INFO:
    *   - Anyone can instruct the contract to burn 2% of the Treasury every 1296000 blocks (approx. 30 days).
    *   - Contract owner cannot burn tokens.
    *
    */     
    function burnTokens() public {
        require(_msgSender() != owner(), "Sender cannot be contract owner");
        require(block.number >= burnBlock, "Burn interval not reached");

        uint256 ownerBalance = balanceOf(owner());
        uint256 burnAmount = (ownerBalance * burnPercent) / 100;

        burnBlock = block.number + BLOCK_INTERVAL;
        _burn(owner(), burnAmount);
    
        emit TokensBurned(owner(), burnAmount);
        emit NewBurnBlock(burnBlock);
    }

    /** 
    *
    * PURPOSE:
    *   - Gets the reward block for an address.
    *
    */     
    function getRewardBlock() public view returns (uint256) {
        if (isBlockNumberRegistered(_msgSender())) {
            return _addressToBlockNumber.get(_msgSender());
        }
        else {
            return 0;
        }
    }

    /** 
    *
    * PURPOSE:
    *   - Gets the reward balance for an address.
    *
    */     
    function getRewardBalance() public view returns (uint256) {
        if (isBalanceRegistered(_msgSender())) {
            return _addressToBalance.get(_msgSender());
        }
        else {
            return 0;
        }
    }

    /** 
    *
    * PURPOSE:
    *   - Checks if block number has been registered for an address.
    *
    */  
    function isBlockNumberRegistered(address addr) private view returns (bool) {
        return _addressToBlockNumber.contains(addr);
    }

     /** 
    *
    * PURPOSE:
    *   - Checks if balance has been registered for an address.
    *
    */  
    function isBalanceRegistered(address addr) private view returns (bool) {
        return _addressToBalance.contains(addr);
    }
    
    /** 
    *
    * PURPOSE:
    *   - Removes ability for contract owner to transfer tokens out of Treasury.
    * INFO:
    *   - Will be called by contract owner once part of the Treasury has been transferred to LP (44%) and Developer (6%) wallets.
    *
    */   
    function disableOwnerTransfers() external onlyOwner {
        isOwnerTranfersDisabled = true;
    }

    /** 
    *
    * PURPOSE:
    *   - Overides transfer function.
    * INFO:
    *   - Restricts contract owner ability to transfer funds.
    *   - Removes reward block number and balance for sender address 
    *
    */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        require(_canTransfer(_msgSender(), recipient), "Sender/recipient is contract owner. Transfer aborted.");
        require(_removeRewardBalance(_msgSender()), "Cannot remove reward balance. Transfer aborted.");
        require(_removeRewardBlock(_msgSender()), "Cannot remove reward block. Transfer aborted.");
        return super.transfer(recipient, amount);
    }

    /** 
    *
    * PURPOSE:
    *   - Overides transferFrom function.
    * INFO:
    *   - Restricts contract owner ability to transfer funds.
    *   - Removes reward block number and balance for sender address
    *
    */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        require(_canTransfer(sender, recipient), "Sender/recipient is contract owner. Transfer aborted.");
        require(_removeRewardBalance(sender), "Cannot remove reward balance. Transfer aborted.");
        require(_removeRewardBlock(sender), "Cannot remove reward block. Transfer aborted.");
        return super.transferFrom(sender, recipient, amount);
    }

    /** 
    *
    * PURPOSE:
    *   - Returns true if account executing transfer is contractOwner and if transfers are disabled.
    * INFO:
    *   - Used by transfer and transferFrom override functions.
    *
    */
    function _canTransfer(address sender, address recipient) internal view returns (bool) {
        if ((sender == owner() || recipient ==  owner()) && isOwnerTranfersDisabled == true) {
            return false;
        }
        return true;
    }

    /** 
    *
    * PURPOSE:
    *   - Removes the reward balance for an address.
    * INFO:
    *   - If an address sends funds from an address that has a reward scheduled, they need to re-execute rewardTokens().
    *
    */
    function _removeRewardBalance(address sender) internal returns (bool) {
        if (isBalanceRegistered(sender)) {
            return _addressToBalance.remove(sender);
        }
        else {
            return true;
        }
    }

    /** 
    *
    * PURPOSE:
    *   - Removes the reward block for an address.
    * INFO:
    *   - If an address sends funds from an address that has a reward scheduled, they need to re-execute rewardTokens().
    *
    */
    function _removeRewardBlock(address sender) internal returns (bool) {
        if (isBlockNumberRegistered(sender)) {
            return _addressToBlockNumber.remove(sender);
        }
        else {
            return true;
        }
    }

    /** 
    *
    * PURPOSE:
    *   - Helper function for doing division.
    *
    */
    function divideAndScale(uint256 numerator, uint256 denominator) private pure returns (uint256 result) {
        require(denominator > 0, "Division by zero");
        result = (numerator * SCALE) / denominator;
    }
 
}
