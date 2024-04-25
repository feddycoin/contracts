// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
* @title Feddy (FEDDY)
* @notice Token burning, yield bearing memecoin. 
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

    uint256 private constant SCALE = 1e18;
    uint256 public constant BLOCK_INTERVAL = 1296000; // Default reward/burn interval is 30 days.
    uint256 public burnBlock;
    uint256 public burnPercent = 2;
    uint256 public rewardPercent = 2;
    bool    public isOwnerTranfersDisabled = false;

    event NewRewardBlock(address indexed addr, uint256 blockNumber);
    event TokensRewarded(address indexed addr, uint256 amount);
    event NewBurnBlock(uint256 blockNumber);
    event TokensBurned(address indexed addr, uint256 amount);

    /** 
    *
    * PURPOSE:
    *   - Rewards tokens from Treasury
    * INFO:
    *   - Each token holder can reward themselves tokens from Treasury every 1296000 blocks (approx. 30 days)
    *   - This function needs to be run by every new token holder to set an initial reward block
    *   - If holder receives tokens from another address, they will need to create a new initial reward block
    *   - Contract owner cannot collect rewards
    *
    */     
    function rewardTokens() public {

        require(_msgSender() != owner(), "Sender cannot be contract owner");
        uint256 ownerBalance = balanceOf(owner());
        require(ownerBalance > 0, "Treasury Balance needs to be greater than 0");
        uint256 holderBalance = balanceOf(_msgSender());
        require(holderBalance > 0, "Senders balance needs to be greater than 0");

        if (!isAddressRegistered(_msgSender())) {
           _addressToBlockNumber.set(_msgSender(), (block.number + BLOCK_INTERVAL));
        }

        uint256 rewardBlock =  _addressToBlockNumber.get(_msgSender());

        if (block.number >= rewardBlock) {    
            uint256 totalRewardAmount = (ownerBalance * rewardPercent) / 100;
            uint256 totalSupply = totalSupply();
            uint256 holdersSupply = totalSupply - ownerBalance;
            uint256 holderPercent = divideAndScale(holderBalance, holdersSupply);
            uint256 transferAmount = (totalRewardAmount * holderPercent) / SCALE;

            _addressToBlockNumber.set(_msgSender(), (block.number + BLOCK_INTERVAL));
            _transfer(owner(), _msgSender(), transferAmount);
            
            emit TokensRewarded(_msgSender(), transferAmount);
        }
           
        emit NewRewardBlock(_msgSender(), _addressToBlockNumber.get(_msgSender()));
        
    }

    /** 
    *
    * PURPOSE:
    *   - Burns tokens from Treasury.
    *
    * INFO:
    *   - Anyone can instruct the contract to burn 2% of the Treasury every 1296000 blocks (approx. 30 days)
    *   - Contract owner cannot burn tokens
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
    *   - Checks if block number has been registered for an address.
    *
    */  
    function isAddressRegistered(address addr) private view returns (bool) {
        return _addressToBlockNumber.contains(addr);
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
    *
    */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        require(_canTransfer(_msgSender()), "Sender is contract owner. Transfer aborted.");
        require(_removeRewardBlock(_msgSender(), recipient), "Cannot remove reward block. Transfer aborted.");
        return super.transfer(recipient, amount);
    }

    /** 
    *
    * PURPOSE:
    *   - Overides transferFrom function.
    * INFO:
    *   - Restricts contract owner ability to transfer funds.
    *
    */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        require(_canTransfer(sender), "Sender is contract owner. Transfer aborted.");
        require(_removeRewardBlock(sender, recipient), "Cannot remove reward block. Transfer aborted.");
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
    function _canTransfer(address sender) internal view returns (bool) {
        if (sender == owner() && isOwnerTranfersDisabled == true) {
            return false;
        }
        return true;
    }

    /** 
    *
    * PURPOSE:
    *   - Removes the reward block for an address.
    * INFO:
    *   - If an address receives funds from an address other than the contract owner, they need to create new reward block.
    *
    */
    function _removeRewardBlock(address sender, address recipient) internal returns (bool) {
        if (isAddressRegistered(recipient) && sender != owner()) {
            return _addressToBlockNumber.remove(recipient);
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
