//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "hardhat/console.sol";

contract DutchRaffle is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public DUTCH_RAFFLE;
    bool public isInitialized = false;

    uint256 precisionFactor  = 10**8;

    IERC20 public rewardTokenAddress;

    constructor() {
        DUTCH_RAFFLE = msg.sender;
    }

    function initialize(IERC20 _rewardTokenAddress) external {
        require(!isInitialized, "Already initialized");
        require(msg.sender == DUTCH_RAFFLE, "Only Owner");
        isInitialized = true;
        rewardTokenAddress = _rewardTokenAddress;
        transferOwnership(msg.sender);
    }

    mapping(uint256 => uint256) public maxSupply;
    mapping(uint256 => uint256) public currentSupply;
    mapping(uint256 => bool) public activeStatus;
    mapping(uint256 => bool) public completedStatus;
    mapping(uint256 => address[]) public raffleAddressList;
    mapping(uint256 => uint256) public startPrice;
    mapping(uint256 => uint256) public endPrice;
    mapping(uint256 => uint256) public startTime;
    mapping(uint256 => uint256) public endTime;

    function startRaffle(uint256 raffleId, uint256 totalSupply, uint256 sPrice, uint256 ePrice, uint256 durationHours) external onlyOwner {
        require(completedStatus[raffleId]==false,"Raffle Already Completed!");
        require(activeStatus[raffleId]==false,"Raffle Not Active");
        activeStatus[raffleId] = true;
        maxSupply[raffleId] = totalSupply;
        currentSupply[raffleId] = 0;
        startPrice[raffleId] = sPrice;
        endPrice[raffleId] = ePrice;
        startTime[raffleId] = block.timestamp;
        endTime[raffleId] = block.timestamp + durationHours*3600 ;
    }

    function updateTokenAddress(IERC20 _address) external onlyOwner {
        rewardTokenAddress = _address;
    }

    function updateTotalDuration(uint256 raffleId, uint256 durationHours) external onlyOwner {
        endTime[raffleId] = startTime[raffleId] + durationHours*3600 ;
    }

    function getCurrentPrice(uint256 raffleId) public view returns(uint256) {
        require(activeStatus[raffleId], "Raffle is inactive");
        require(!completedStatus[raffleId],"Raffle Already Completed!");
        if(endTime[raffleId] < block.timestamp)
        {
            return endPrice[raffleId];
        }
        else{
            uint256 pricePerTime = (startPrice[raffleId] - endPrice[raffleId])*precisionFactor/(endTime[raffleId] - startTime[raffleId]);
            uint256 priceChange = pricePerTime*(block.timestamp - startTime[raffleId])/precisionFactor;
            return startPrice[raffleId] - priceChange;
        }
    }

    function endRaffle(uint256 raffleId) onlyOwner external {
        activeStatus[raffleId] = false;
        completedStatus[raffleId] = true;
    }

    function buyRaffle(uint256 raffleId, uint256 amount) external {
        require(activeStatus[raffleId], "Raffle is inactive");
        require(!completedStatus[raffleId],"Raffle Already Completed!");
        require(block.timestamp <= endTime[raffleId], "Raffle has ended");
        require(currentSupply[raffleId].add(1) <= maxSupply[raffleId], "Total Limit Reached");
        uint256 currentPrice = getCurrentPrice(raffleId);
        require(amount >= currentPrice,"Amount is less than price");
        require(rewardTokenAddress.balanceOf(msg.sender) >= amount.mul(10**18), "Insufficient Amount");
        rewardTokenAddress.transferFrom(msg.sender, address(this), amount.mul(10**18));
        raffleAddressList[raffleId].push(msg.sender);
        currentSupply[raffleId] += 1;
    }

    function getRaffleAddressList(uint256 raffleId) external view returns (address[] memory) {
        return raffleAddressList[raffleId];
    } 

    function getRaffleDetails(uint256 raffleId) external view returns (uint256, uint256, uint256, uint256, uint256, uint256){
        return (maxSupply[raffleId], currentSupply[raffleId], startPrice[raffleId], endPrice[raffleId], startTime[raffleId], endTime[raffleId]);
    }

    function withdraw() external onlyOwner {
        uint256 balance = rewardTokenAddress.balanceOf(address(this));
        rewardTokenAddress.transfer(msg.sender, balance);
    }
}