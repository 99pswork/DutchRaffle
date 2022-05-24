//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "hardhat/console.sol";

contract DutchRaffleContract is Ownable {
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

    struct User{
        address ownerAddress;
        uint256 raffleId;
        uint256 usedTokens;
    }

    struct DutchRaffle {
        uint256 raffleId;
        uint256 maxSupply;
        uint256 currentSupply;
        bool activeStatus;
        bool completedStatus;
        address[] raffleAddressList;
        uint256 startPrice;
        uint256 endPrice;
        uint256 startTime;
        uint256 endTime;
    }

    mapping(uint256 => DutchRaffle) public getDutchRaffle;
    mapping(address => User[]) public userDetails;

    uint256[] public completedRaffleList;
    uint256[] public activeRaffleList;

    function startRaffle(uint256 raffleId, uint256 totalSupply, uint256 sPrice, uint256 ePrice, uint256 durationHours) external onlyOwner {
        DutchRaffle memory dutchRaffle = getDutchRaffle[raffleId];
        require(dutchRaffle.completedStatus==false,"Raffle Already Completed!");
        require(dutchRaffle.activeStatus==false,"Raffle Not Active");
        dutchRaffle.activeStatus = true;
        dutchRaffle.completedStatus = false;
        dutchRaffle.maxSupply = totalSupply;
        dutchRaffle.currentSupply = 0;
        dutchRaffle.startPrice = sPrice;
        dutchRaffle.endPrice = ePrice;
        dutchRaffle.startTime = block.timestamp;
        dutchRaffle.endTime = block.timestamp + durationHours*3600;
        getDutchRaffle[raffleId] = dutchRaffle;
        activeRaffleList.push(raffleId);
    }

    function updateTokenAddress(IERC20 _address) external onlyOwner {
        rewardTokenAddress = _address;
    }

    function updateTotalDuration(uint256 raffleId, uint256 durationHours) external onlyOwner {
        DutchRaffle storage dutchRaffle = getDutchRaffle[raffleId];
        require(dutchRaffle.completedStatus==false, "Raffle has completed!");
        dutchRaffle.endTime = dutchRaffle.startTime + durationHours*3600 ;
    }

    function getCurrentPrice(uint256 raffleId) public view returns(uint256) {
        DutchRaffle memory dutchRaffle = getDutchRaffle[raffleId];
        require(dutchRaffle.activeStatus, "Raffle is inactive");
        require(!dutchRaffle.completedStatus,"Raffle Already Completed!");
        if(dutchRaffle.endTime < block.timestamp)
        {
            return dutchRaffle.endPrice;
        }
        else{
            uint256 pricePerTime = (dutchRaffle.startPrice - dutchRaffle.endPrice)*precisionFactor/(dutchRaffle.endTime - dutchRaffle.startTime);
            uint256 priceChange = pricePerTime*(block.timestamp - dutchRaffle.startTime)/precisionFactor;
            return dutchRaffle.startPrice - priceChange;
        }
    }

    function removeActiveRaffle(uint256 raffleId) internal {
        uint256 index = 0;
        bool flag = false;
        for(uint256 i=0; i<activeRaffleList.length; i++)
        {
            if(activeRaffleList[i] == raffleId){
                index = i;
                flag = true;
            }
        }
        if(flag)
        {
            activeRaffleList[index] = activeRaffleList[activeRaffleList.length -1];
            activeRaffleList.pop();
        }
    }

    function endRaffle(uint256 raffleId) onlyOwner external {
        DutchRaffle storage dutchRaffle = getDutchRaffle[raffleId];
        require(dutchRaffle.completedStatus==false, "Raffle has already completed!");
        dutchRaffle.activeStatus = false;
        dutchRaffle.completedStatus = true;
        completedRaffleList.push(raffleId);
        removeActiveRaffle(raffleId);
        getDutchRaffle[raffleId] = dutchRaffle;
    }

    function buyRaffle(uint256 raffleId, uint256 amount) external {
        DutchRaffle storage dutchRaffle = getDutchRaffle[raffleId];
        require(dutchRaffle.activeStatus, "Raffle is inactive");
        require(!dutchRaffle.completedStatus,"Raffle Already Completed!");
        require(block.timestamp <= dutchRaffle.endTime, "Raffle has ended");
        require(dutchRaffle.currentSupply.add(1) <= dutchRaffle.maxSupply, "Total Limit Reached");
        uint256 currentPrice = getCurrentPrice(raffleId);
        require(amount >= currentPrice,"Amount is less than price");
        require(rewardTokenAddress.balanceOf(msg.sender) >= amount.mul(10**18), "Insufficient Amount");
        rewardTokenAddress.transferFrom(msg.sender, address(this), amount.mul(10**18));
        dutchRaffle.raffleAddressList.push(msg.sender);
        dutchRaffle.currentSupply += 1;
        User memory userTemp;
        userTemp.ownerAddress = msg.sender;
        userTemp.raffleId = raffleId;
        userTemp.usedTokens += amount;
        userDetails[msg.sender].push(userTemp);
        getDutchRaffle[raffleId] = dutchRaffle;
    }

    function getRaffleAddressList(uint256 raffleId) external view returns (address[] memory) {
        return getDutchRaffle[raffleId].raffleAddressList;
    } 

    function getRaffleDetails(uint256 raffleId) external view returns (DutchRaffle memory){
        return getDutchRaffle[raffleId];
    }

    function getAllActiveRaffle() view external returns (DutchRaffle[] memory) {
        DutchRaffle[] memory dutchRaffle = new DutchRaffle[](activeRaffleList.length);
        for(uint256 i=0;i<activeRaffleList.length;i++){
            dutchRaffle[i] = getDutchRaffle[activeRaffleList[i]];
        }
        return dutchRaffle;
    }

    function getAllUserDetails(address _address) view external returns (User[] memory) {
        return userDetails[_address];
    }

    function getAllCompletedRaffle() view external returns (DutchRaffle[] memory) {
        DutchRaffle[] memory dutchRaffle = new DutchRaffle[](completedRaffleList.length);
        for(uint256 i=0; i<completedRaffleList.length; i++){
            dutchRaffle[i] = getDutchRaffle[completedRaffleList[i]];
        }
        return dutchRaffle;
    }

    function withdraw() external onlyOwner {
        uint256 balance = rewardTokenAddress.balanceOf(address(this));
        rewardTokenAddress.transfer(msg.sender, balance);
    }
}