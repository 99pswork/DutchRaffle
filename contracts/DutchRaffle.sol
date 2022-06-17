//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

interface IAlphaSharkRewards {
    function updateTotalLockTokens(uint256 _amount, address _address) external;
    function availableTokens(address _address) external view returns (uint256);
}

contract DutchRaffleContract is Ownable, ReentrancyGuard, AccessControl {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public DUTCH_RAFFLE;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bool public isInitialized = false;

    uint256 precisionFactor  = 10**8;

    address public AlphaSharkRewards;

    constructor() ReentrancyGuard() {
        DUTCH_RAFFLE = msg.sender;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function initialize(address _rewardsContractAddress) external nonReentrant {
        require(!isInitialized, "Already initialized");
        require(msg.sender == DUTCH_RAFFLE, "Only Owner");
        isInitialized = true;
        AlphaSharkRewards = _rewardsContractAddress;
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

    function startRaffle(uint256 raffleId, uint256 totalSupply, uint256 sPrice, uint256 ePrice, uint256 durationHours, uint256 startTime) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not a admin");
        DutchRaffle memory dutchRaffle = getDutchRaffle[raffleId];
        require(dutchRaffle.completedStatus==false,"Raffle Already Completed!");
        require(dutchRaffle.activeStatus==false,"Raffle Not Active");
        dutchRaffle.raffleId = raffleId;
        dutchRaffle.activeStatus = true;
        dutchRaffle.completedStatus = false;
        dutchRaffle.maxSupply = totalSupply;
        dutchRaffle.currentSupply = 0;
        dutchRaffle.startPrice = sPrice;
        dutchRaffle.endPrice = ePrice;
        dutchRaffle.startTime = startTime;
        dutchRaffle.endTime = startTime + durationHours*3600;
        getDutchRaffle[raffleId] = dutchRaffle;
        activeRaffleList.push(raffleId);
    }

    function updateRewardContractAddress(address _address) external onlyOwner {
        AlphaSharkRewards = _address;
    }

    function updateTotalDuration(uint256 raffleId, uint256 durationHours) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not a admin");
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
        else if(dutchRaffle.startTime > block.timestamp){
            return dutchRaffle.startPrice;
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

    function endRaffle(uint256 raffleId) public {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not a admin");
        DutchRaffle storage dutchRaffle = getDutchRaffle[raffleId];
        require(dutchRaffle.completedStatus==false, "Raffle has already completed!");
        dutchRaffle.activeStatus = false;
        dutchRaffle.completedStatus = true;
        completedRaffleList.push(raffleId);
        removeActiveRaffle(raffleId);
        getDutchRaffle[raffleId] = dutchRaffle;
    }

    function updateRaffleStatus() external {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not a admin");
         for(uint256 i=0; i<activeRaffleList.length; i++)
        {
            DutchRaffle memory _dutchRaffle = getDutchRaffle[activeRaffleList[i]];
            if(_dutchRaffle.endTime < block.timestamp){
                endRaffle(activeRaffleList[i]);
                i-=1;
            }
        }
    }

    function buyRaffle(uint256 raffleId, uint256 amount, address _address) external nonReentrant {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not a admin");
        DutchRaffle storage dutchRaffle = getDutchRaffle[raffleId];
        require(dutchRaffle.activeStatus, "Raffle is inactive");
        require(!dutchRaffle.completedStatus,"Raffle Already Completed!");
        require(dutchRaffle.startTime <= block.timestamp, "Dutch auction has not started yet");
        require(block.timestamp <= dutchRaffle.endTime, "Raffle has ended");
        require(dutchRaffle.currentSupply.add(1) <= dutchRaffle.maxSupply, "Total Limit Reached");
        uint256 currentPrice = getCurrentPrice(raffleId);
        require(amount >= currentPrice,"Amount is less than price");
        require(IAlphaSharkRewards(AlphaSharkRewards).availableTokens(_address) >= amount.mul(10**18), "Insufficient Balance");
        IAlphaSharkRewards(AlphaSharkRewards).updateTotalLockTokens(amount.mul(10**18), _address);
        dutchRaffle.raffleAddressList.push(_address);
        dutchRaffle.currentSupply += 1;
        User memory userTemp;
        userTemp.ownerAddress = _address;
        userTemp.raffleId = raffleId;
        userTemp.usedTokens += amount;
        userDetails[_address].push(userTemp);
        getDutchRaffle[raffleId] = dutchRaffle;
    }

    function getRaffleAddressList(uint256 raffleId) external view returns (address[] memory) {
        return getDutchRaffle[raffleId].raffleAddressList;
    } 

    function getRaffleDetails(uint256 raffleId) external view returns (DutchRaffle memory){
        return getDutchRaffle[raffleId];
    }

    function getAllActiveRaffle() view public returns (DutchRaffle[] memory) {
        DutchRaffle[] memory dutchRaffle = new DutchRaffle[](activeRaffleList.length);
        for(uint256 i=0;i<activeRaffleList.length;i++){
            dutchRaffle[i] = getDutchRaffle[activeRaffleList[i]];
        }
        return dutchRaffle;
    }

    function getAllUserDetails(address _address) view public returns (User[] memory) {
        return userDetails[_address];
    }

    function getAllCompletedRaffle() view public returns (DutchRaffle[] memory) {
        DutchRaffle[] memory dutchRaffle = new DutchRaffle[](completedRaffleList.length);
        for(uint256 i=0; i<completedRaffleList.length; i++){
            dutchRaffle[i] = getDutchRaffle[completedRaffleList[i]];
        }
        return dutchRaffle;
    }

    function getAllData(address _address) view external returns (DutchRaffle[] memory, User[] memory, DutchRaffle[] memory){
        return (getAllActiveRaffle(), getAllUserDetails(_address), getAllCompletedRaffle());
    }

    function getActiveRaffleList() view external returns (uint256[] memory){
        return activeRaffleList;
    }

    function getCompletedRaffleList() view external returns (uint256[] memory){
        return completedRaffleList;
    } 

}