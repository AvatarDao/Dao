// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface ERC20Decimal {
    function decimals() external view returns (uint256);
}

contract Avatar is Initializable, ERC721Upgradeable, ERC721EnumerableUpgradeable, OwnableUpgradeable, UUPSUpgradeable {

    // safe transfer ERC20
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // ****  STORAGE START (only add, not delete or modify)   **** */
    uint256 constant proposalTime = 7 days;
    uint256 constant daoRunTime = 730 days;

    address private operateAddress;
    address private tokenAddress; 
    uint256 private tokenDecimal;
    uint256 private votePrice; 
    uint256 private voteFee;   
    uint256 private votesTotal; 
    uint256 private endTime; 
    uint256 private joinDeadline;    
    uint256 private withdrawMaxAmt;
    uint256 private withdrawDayAmt;
    uint256 private withdrawLastTime;
    uint8   private passVoteRate;
    bool    private lock;

    //**  settlment  */
    bool public settlementSwitch;
    uint256 public settlementTotalAvgAmt;

     /** ADMIN  */
    mapping(address => bool) public membersWhiteList;
    mapping(address => bool) public admins;
    mapping(address => uint256) public receiverAddressWhiteList;

    //**  proposal  */
    enum Vote {
        Null,
        Yes,
        No
    }

    struct Proposal {
        address proposer;
        uint256 id;
        uint256 applyAmt; 
        uint256 yesVotes;
        uint256 noVotes;
        uint256 totalVotes;
        uint256 deadline;
        uint256 execuredDeadline;
        bool state;
        /** Support call */
        bool executed;
        address[] targets; //call address
        string[] signatures; // call functions
        bytes[] calldatas; // call data
        mapping(uint256 => Vote) votesByMember;
        mapping(uint256 => address) tokenIdByMember;
    }

    uint256 public proposalCount;
    mapping (uint256 => Proposal) public proposals;
    mapping (address => bool) public proposalTargetAddress;

    // ****  STORAGE END ****


    //**  EVENTS */
    event MemberJoin(address indexed member, uint256 amount, uint8 votes, uint256[] tokenIds);
    event SubmitVote(uint256 indexed proposalId, address indexed member, uint256 indexed tokenId, Vote vote);
    event SummitProposal(uint256 indexed proposalId, address indexed proposer, uint256 amt, address[] targets, string[] signatures, bytes[] calldatas, string description);
    event ProposalPassed(uint256 indexed proposalId, address indexed proposer, uint256 amt);
    event SettlementProfit(address indexed member, uint256 indexed tokenId, uint256 amt);
    event SettlementRefund(address indexed mmeber, uint256 indexed tokenId, uint256 amt);
    event Settlement(uint256 amount, uint256 avgAmt, uint256 time);
    event ProposalExecuteSuccess(uint256 indexed proposalId);
    event ProposalExecutedInfo(uint256 indexed proposalId, address target, string signature, bytes data, bytes result);
    event MemberJoinDedline(uint256 time);
    event SetAdmin(address admin, bool state);
    event AddWhiteMember(address member);
    event SetTargetAddress(address target, bool state);

    //** MODIFER */
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
    

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(
        address _operateAddress,
        address _tokenAddress, //ERC20 contract
        address _superAdmin,
        uint256 _votePrice,
        uint256 _voteFee,
        uint256 _votesTotal,
        uint256 _withdrawMaxAmt,
        uint8 _passVoteRate,
        string memory _name,
        string memory _symbol
    ) initializer public {

        __ERC721_init(_name, _symbol);
        __ERC721Enumerable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

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

    function _authorizeUpgrade(address newImplementation) internal view override
    {
        require(msg.sender == address(this));
        require(newImplementation != address(0));
    }    

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function setOperateAddress(address _addr) external onlyOwner {
        require(_addr != address(0));
        require(operateAddress != _addr);
        operateAddress = _addr;
    }

    function setJoinDeadline(uint time) external onlyOwner {
        require(time > block.timestamp,"time must be greater than the current time");
        joinDeadline = time;
        emit MemberJoinDedline(time);
    }

    /**
     * @dev Set management address.
     */
    function setAdmin(address _address, bool state) external onlyOwner{
        require(_address != address(0));
        require(admins[_address] != state , "address error");
        admins[_address] = state;
        emit SetAdmin(_address, state);
    }

    /**
     * @dev Set target address.
     */
    function setPropsalTargetAddress(address _address, bool state) external onlyOwner{
        require(_address != address(0));
        require(proposalTargetAddress[_address] != state , "address error");
        proposalTargetAddress[_address] = state;
        emit SetTargetAddress(_address, state);
    }



    /**
     * @dev Add whitelist address.
     */
    function submitWhiteMember(address _address) external onlyAdmin {
        require(! membersWhiteList[_address], "address already exists");
        membersWhiteList[_address] = true;
        emit AddWhiteMember(_address);
    }

    /**
     * @dev Add Add proposal whitelist address.
     */
    function submitReceiverAddressWhite(address _address, uint256 _amt) external onlyAdmin {
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
        require(joinDeadline == 0 || joinDeadline > block.timestamp, "ended");

        uint256 amount = votePrice * _count;
        uint256 fee = voteFee * _count;

        IERC20Upgradeable ERC20token = IERC20Upgradeable(tokenAddress);

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
        uint256 _applyAmt,
        string memory description,
        address[] memory targets,
        string[] memory signatures,
        bytes[] memory calldatas
    ) external onlyAdmin noReentrant returns (uint256) {
        _applyAmt = _applyAmt * tokenDecimal;
        require(_proposer != address(0),"_proposer address cant be 0");
        require(IERC20Upgradeable(tokenAddress).balanceOf(address(this)) >= _applyAmt,"Insufficient contract assets");
        require(targets.length < 10,"target length error");
        require(receiverAddressWhiteList[_proposer] > _applyAmt || _applyAmt <= withdrawMaxAmt,"exceeding the maximum limit of a single transaction");
        require(targets.length == targets.length && targets.length == signatures.length && targets.length == calldatas.length, "proposal function information arity mismatch");
            
        for(uint i; i < targets.length; i++){
            require(proposalTargetAddress[targets[i]],"Target address not allowed");
        }

        proposalCount++;

        Proposal storage proposal = proposals[_proposalId];

        require(proposal.proposer == address(0),"Non repeatable");

        proposal.id = _proposalId;
        proposal.proposer = _proposer; 
        proposal.applyAmt = _applyAmt;
        proposal.yesVotes = 0;
        proposal.noVotes = 0;
        proposal.deadline = 0;
        proposal.state = false;
        proposal.executed = false;
        proposal.targets = targets;
        proposal.signatures = signatures;
        proposal.calldatas = calldatas;

        emit SummitProposal(_proposalId, _proposer, _applyAmt, targets, signatures, calldatas, description);

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
            proposal.execuredDeadline = block.timestamp + 3 days;

            if(proposal.applyAmt > 0){
                //There is no limit on the address of the white list
                if(receiverAddressWhiteList[proposal.proposer] < proposal.applyAmt){
                    require(beforeWithdraw(proposal.applyAmt),"Withdrawal limit exceeded");
                }
                
                IERC20Upgradeable(tokenAddress).safeTransfer(proposal.proposer, proposal.applyAmt);
            }

            emit ProposalPassed(_proposalId, proposal.proposer, proposal.applyAmt);
        } 
    } 


    /**
     * @dev Exe of proposal.
     */
    function execute(uint _proposalId) external noReentrant {
        Proposal storage proposal = proposals[_proposalId];
        require(! proposal.executed,"The proposal has been implemented");
        require(proposal.state,"The proposal was not adopted");
        require(proposal.execuredDeadline > block.timestamp, "Proposal implementation has expired");
        require(proposal.id > 0, "Proposal invalid");

        proposal.executed = true;

        for (uint i = 0; i < proposal.targets.length; i++) {

            bytes memory callData;
            if (bytes(proposal.signatures[i]).length == 0) {
                callData = proposal.calldatas[i];
            } else {
                callData = abi.encodePacked(bytes4(keccak256(bytes(proposal.signatures[i]))), proposal.calldatas[i]);
            }

            (bool success, bytes memory data) = address(proposal.targets[i]).call(callData);
            require(success, "Transaction execution reverted.");

            emit ProposalExecutedInfo(proposal.id, proposal.targets[i], proposal.signatures[i], proposal.calldatas[i], data);

        }   

        emit ProposalExecuteSuccess(proposal.id);
    }


    /**
     * @dev settlement profit.
     */ 
    function settlement() external noReentrant onlyAdmin {
        uint256 count = totalSupply();
        require(count > 0,"Dao not started");
        require(settlementSwitch,"Settlement not started");

        IERC20Upgradeable ERC20token = IERC20Upgradeable(tokenAddress);
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

    function getActions(uint _proposalId) 
        public 
        view 
        returns (
            address[] memory targets, 
            string[] memory signatures, 
            bytes[] memory calldatas
    ) {
        Proposal storage proposal = proposals[_proposalId];
        return (proposal.targets, proposal.signatures, proposal.calldatas);
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


    function version() public pure returns(string memory){
        return "v2";
    }
}