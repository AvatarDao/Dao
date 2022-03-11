// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

interface ERC20Decimal {
    function decimals() external view returns (uint256);
}

abstract contract Ownable is Context {

    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor (address owner_) {
        _owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract AvatarDao is ERC721, ERC721Enumerable, Ownable {

    using SafeERC20 for IERC20;

    // *******************
    // GLOBAL PARAMS
    // *******************
    address private operateAddress;
    address private tokenAddress; 
    uint256 private tokenDecimal;
    uint256 private votePrice; 
    uint256 private voteFee;   
    uint256 private votesTotal; 
    uint256 private endTime;     
    uint256 private withdrawMaxAmt;
    uint256 private withdrawDayAmt;
    uint256 private withdrawLastTime;
    uint8 private passVoteRate;
    
    bool private lock;

    uint256 constant proposalTime = 7 days;
    uint256 constant daoRunTime = 730 days;


    mapping(address => bool) public membersWhiteList;
    mapping(address => bool) public admins;
    mapping(address => uint256) public receiverAddressWhiteList;

    // *******************
    // SETTLEMENT
    // *******************
    bool public settlementSwitch;
    uint256 public settlementTotalAvgAmt;

    // *******************
    // PROPOSAL
    // *******************
    enum Vote {
        Null,
        Yes,
        No
    }

    struct Proposal {
        address proposer;
        uint256 applyAmt; 
        uint256 yesVotes;
        uint256 noVotes;
        uint256 totalVotes;
        uint256 deadline;
        bool state;
        mapping(uint256 => Vote) votesByMember;
        mapping(uint256 => address) tokenIdByMember;
    }

    uint256 public proposalCount;
    mapping (uint256 => Proposal) public proposals;


    // *******************
    // EVENTS
    // *******************
    event MemberJoin(address indexed member, uint256 amount, uint8 votes, uint256[] tokenIds);
    event SubmitVote(uint256 indexed proposalId, address indexed member, uint256 indexed tokenId, Vote vote);
    event SummitProposal(uint256 indexed proposalId, address indexed proposer, uint256 amt);
    event ProposalPassed(uint256 indexed proposalId, address indexed proposer, uint256 amt);
    event SettlementProfit(address indexed member, uint256 indexed tokenId, uint256 amt);
    event SettlementRefund(address indexed mmeber, uint256 indexed tokenId, uint256 amt);
    event Settlement(uint256 amount, uint256 avgAmt, uint256 time);

    

    // *******************
    // MODIFER FUNCTIONS
    // *******************
    modifier noReentrant() {
        require(lock, "noReentrant call");
        
        lock = false;

        _;

        lock = true;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], "only admin");
        _;
    }

    modifier onlyMemberWhite() {
        require(membersWhiteList[msg.sender],"Not on the white list");
        _;
    }

    constructor(
        address _operateAddress,
        address _tokenAddress, //The token will validate the contract instance and must be standard erc20 Transfer requires bool to be returned
        address _superAdmin,
        uint256 _votePrice,
        uint256 _voteFee,
        uint256 _votesTotal,
        uint256 _withdrawMaxAmt,
        uint8 _passVoteRate,
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) Ownable(_superAdmin) {

        require(_tokenAddress != address(0),"token address cannot be 0");

        uint256 decimal = ERC20Decimal(_tokenAddress).decimals();

        require(decimal > 0, "ERC20 decimal canot be 0");
        require(_operateAddress != address(0),"operate address cannot be 0");
        require(_superAdmin != address(0),"_admin address cannot be 0");
        require(_votesTotal > 0,"nft must be greater than 0");
        require(_voteFee < _votePrice && _votePrice > 0,"nft fee error");
        require(_passVoteRate > 0 && _passVoteRate <= 100,"params error : _passVoteRate 1-100");

        tokenDecimal = 10 ** decimal;
        operateAddress = _operateAddress;
        tokenAddress = _tokenAddress;
        votesTotal = _votesTotal;
        votePrice = _votePrice * tokenDecimal;
        voteFee = _voteFee * tokenDecimal;
        withdrawMaxAmt = _withdrawMaxAmt * tokenDecimal;
        passVoteRate = _passVoteRate;
        lock = true;
        admins[_superAdmin] = true;
    }   

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function setOperateAddress(address _addr) external onlyOwner {
        require(_addr != address(0));
        require(operateAddress != _addr);
        operateAddress = _addr;
    }

    /**
     * @dev Add management address.
     */
    function submitAdmin(address _address) public onlyOwner {
        require(! admins[_address], "address already exists");
        admins[_address] = true;
    }

    /**
     * @dev Del management address.
     */
    function delAdmin(address _address) public onlyOwner {
        require(admins[_address], "address non-existent");
        delete admins[_address];
    }

    /**
     * @dev Add whitelist address.
     */
    function submitWhiteMember(address _address) public onlyAdmin {
        require(! membersWhiteList[_address], "address already exists");
        membersWhiteList[_address] = true;
    }

    /**
     * @dev Add Add proposal whitelist address.
     */
    function submitReceiverAddressWhite(address _address, uint256 _amt) public onlyAdmin {
        receiverAddressWhiteList[_address] = _amt;
    }

    /**
     * @dev Fund settlement switch.
     */
    function setSettlementSwitch(bool _state) external onlyOwner {
        settlementSwitch = _state;
    }


    /**
     * @dev Apply for casting NFT.
     */
    function memberJoin(uint8 _count) public onlyMemberWhite noReentrant {
        require(_count <= 3 && _count > 0, "The count scope 1 - 3");
        require(totalSupply() + _count <= votesTotal,"Total limit exceeded");
        require(membersWhiteList[msg.sender], "Not on the white list");

        uint256 amount = votePrice * _count;
        uint256 fee = voteFee * _count;

        IERC20 ERC20token = IERC20(tokenAddress);

        ERC20token.safeTransferFrom(msg.sender, address(this), amount);
        ERC20token.safeTransfer(operateAddress, fee);
     
        // mint nft for vote
        uint256[] memory tokenIds = new uint256[](_count);
        for(uint8 i = 0; i < _count; i++){
            uint256 tokenId = totalSupply() + 1;
            _safeMint(msg.sender, tokenId);
            tokenIds[i] = tokenId;
        }

        if(totalSupply() == votesTotal){
            endTime = block.timestamp + daoRunTime;
        }

        emit MemberJoin(msg.sender, amount, _count, tokenIds);
    }
        
    /**
     * @dev Submission of proposals.
     */    
    function submitProposal(
        uint256 _proposalId,
        address _proposer, 
        uint256 _applyAmt
    ) external onlyAdmin noReentrant returns (uint256) {

        _applyAmt = _applyAmt * tokenDecimal;
        require(_proposer != address(0),"_proposer address cant be 0");
        require(IERC20(tokenAddress).balanceOf(address(this)) >= _applyAmt,"Insufficient contract assets");
        require(receiverAddressWhiteList[_proposer] > _applyAmt || _applyAmt <= withdrawMaxAmt,"exceeding the maximum limit of a single transaction");
      
        proposalCount++;

        Proposal storage proposal = proposals[_proposalId];

        require(proposal.proposer == address(0),"Non repeatable");

        proposal.proposer = _proposer; 
        proposal.applyAmt = _applyAmt;
        proposal.yesVotes = 0;
        proposal.noVotes = 0;
        proposal.deadline = 0;
        proposal.state = false;

        emit SummitProposal(_proposalId, _proposer, _applyAmt);

        return proposalCount;
    }


    /**
     * @dev Submit vote of proposal.
     */ 
    function submitVote(uint256 _proposalId, Vote _vote) external noReentrant {
        
        uint256 count = balanceOf(msg.sender);
        Proposal storage proposal = proposals[_proposalId];
        require(_vote != Vote.Null,"Wrong voting type");
        require(count > 0, "No voting rights");
        require(proposal.proposer != address(0),"The proposal is invalid");
        require(! proposal.state,"The proposal is closed");

        uint256 votes;
        for(uint256 i = 0; i < count; i++){
            uint256 tokenId = tokenOfOwnerByIndex(msg.sender,i);
            if(tokenId > 0 && proposal.tokenIdByMember[tokenId] == address(0)){
                if(proposal.deadline == 0 || block.timestamp <= proposal.deadline){
                    
                    votes ++;
                   
                    if(_vote == Vote.Yes){
                        proposal.yesVotes = proposal.yesVotes + 1;
                    }  

                    if(_vote == Vote.No){
                        proposal.noVotes = proposal.noVotes + 1;
                    }

                    proposal.votesByMember[tokenId] = _vote;
                    proposal.tokenIdByMember[tokenId] = msg.sender;

                    if(proposal.yesVotes >= 3 && proposal.deadline == 0){
                        proposal.deadline = block.timestamp + proposalTime;
                    }

                    emit SubmitVote(_proposalId, msg.sender, tokenId, _vote);
                }
            }
        }
        
        require(votes > 0,"No valid ticket exists");

        if(getProp(proposal.yesVotes, totalSupply()) >= passVoteRate && ! proposal.state){

            proposal.state = true;
            proposal.totalVotes = totalSupply();

            if(proposal.applyAmt > 0){
                //There is no limit on the address of the white list
                if(receiverAddressWhiteList[proposal.proposer] < proposal.applyAmt){
                    require(beforeWithdraw(proposal.applyAmt),"Withdrawal limit exceeded");
                }
                
                IERC20(tokenAddress).safeTransfer(proposal.proposer, proposal.applyAmt);
            }

            emit ProposalPassed(_proposalId, proposal.proposer, proposal.applyAmt);
        }
    } 

    /**
     * @dev settlement profit.
     */ 
    function settlement() external noReentrant onlyAdmin {
        uint256 count = totalSupply();
        require(count > 0,"Dao not started");
        require(settlementSwitch,"Settlement not started");

        IERC20 ERC20token = IERC20(tokenAddress);
        uint256 balance = ERC20token.balanceOf(address(this));
        uint256 avg = balance / count;
        require(balance > 0 && avg > 0,"Insufficient profit amount");

        for(uint256 i=1; i<=count; i++){
            address tokenIdOfOwner = ownerOf(i);
            try ERC20token.transfer(tokenIdOfOwner, avg) {
                emit SettlementProfit(tokenIdOfOwner, i, avg);
            } catch {
                emit SettlementRefund(tokenIdOfOwner, i, avg);
            }
        }  

        settlementTotalAvgAmt += avg;
        settlementSwitch = false;
        
        emit Settlement(balance, avg, block.timestamp);
    }

    
    // *******************
    // Help Functions
    // *******************
    function configView() external view returns(
        address _operateAddress,
        address _tokenAddress,
        uint256 _tokenDecimal,
        uint256 _votePrice,
        uint256 _voteFee,
        uint256 _votesTotal,
        uint256 _endTime,
        uint256 _withdrawMaxAmt,
        uint256 _passVoteCount,
        bool _settlementSwitch,
        uint256 _settlementTotalAmt,
        uint256 _proposalCount,
        uint256 _totalSupply
    ){
        _operateAddress = operateAddress;
        _tokenAddress = tokenAddress;
        _tokenDecimal = tokenDecimal;
        _votePrice = votePrice;
        _voteFee = voteFee;
        _votesTotal = votesTotal;
        _endTime = endTime;
        _withdrawMaxAmt = withdrawMaxAmt;
        _passVoteCount = passVoteRate;
        _settlementSwitch = settlementSwitch;
        _settlementTotalAmt = settlementTotalAvgAmt;
        _proposalCount = proposalCount;
        _totalSupply = totalSupply();
    }

    function getProposalInfo(uint256 _proposalId) 
        external 
        view 
        returns(
            address proposer, 
            uint256 applyAmt, 
            uint256 yesVotes, 
            uint256 noVotes,
            uint256 totalVotes,
            uint256 deadline,
            bool state,
            uint256 votes
    ) {
        Proposal storage proposal = proposals[_proposalId];

        proposer = proposal.proposer;
        applyAmt = proposal.applyAmt;
        yesVotes = proposal.yesVotes;
        noVotes = proposal.noVotes;
        totalVotes = proposal.totalVotes;
        deadline = proposal.deadline;
        state = proposal.state;
       
        for(uint256 i=0; i<balanceOf(msg.sender); i++){
            uint256 tokenId = tokenOfOwnerByIndex(msg.sender,i);
            if(tokenId > 0 && proposal.tokenIdByMember[tokenId] == address(0)){
                votes += 1;
            }
        }
    }

    function balanceERC20() public view returns(uint256){
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function getNftForPropsal(uint256 _proposalId, uint256 _tokenId) 
        public 
        view 
        returns(
            address member,
            Vote vote
        ){
        Proposal storage proposal = proposals[_proposalId];
        member = proposal.tokenIdByMember[_tokenId];
        vote = proposal.votesByMember[_tokenId];
    }

    function getProp(uint256 _a, uint256 _b) internal pure returns(uint256){
        if(_b == 0){
            return 0;
        }else{
            return _a * 100 / _b;
        }
    }

     /**
     * @dev Limit withdrawal amount within 24 hours.
     */ 
    function beforeWithdraw(uint256 _amt) internal returns(bool){
        if(_amt == 0){
            return true;
        }

        if(block.timestamp - withdrawLastTime > 86400){
            withdrawLastTime = block.timestamp;
            withdrawDayAmt = _amt;
        }else{
            withdrawDayAmt += _amt;
        }

        return withdrawMaxAmt >= withdrawDayAmt;
    }

    function withdrawView() external view returns(
        uint256,
        uint256,
        uint256
    ){
        return (withdrawMaxAmt, withdrawDayAmt, withdrawLastTime);
    }
}
