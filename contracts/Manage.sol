// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./AvatarDao.sol";

contract Manage is Ownable {

    uint256 public count;
    mapping (uint256 => address) public daos;

    constructor () Ownable(msg.sender){

    }

    function publish(
        address _operateAddress,
        address _tokenAddress,
        uint256 _votePrice,
        uint256 _voteFee,
        uint256 _votesTotal,
        uint256 _withdrawMaxAmt,
        uint8 _passVoteRate,
        string memory _name,
        string memory _symbol
    ) public onlyOwner returns(address){

        AvatarDao daoContract = new AvatarDao(
            _operateAddress, 
            _tokenAddress, 
            msg.sender, 
            _votePrice, 
            _voteFee,
            _votesTotal,
            _withdrawMaxAmt,
            _passVoteRate,
            _name,
            _symbol
           );
        
        count++;
        
        daos[count] = address(daoContract);

        return daos[count];
    }
}