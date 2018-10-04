pragma solidity ^0.4.23;

import './1GDOCBase.sol';

contract GDOCReFund is SafeMath { //DAICO合约
    GDOCBase internal gdocbase;

    address private owner;
    address private baseAddress;
    uint256 private yesCounter = 0;
    uint256 private noCounter = 0;
    bool private votingStatus = false;
    bool private finalized = false;
    uint256 private startTime;
    uint256 private endTime;

    enum FundState {
        preRefund,
        ContributorRefund,
        TeamWithdraw,
        Refund
    }
    FundState private state = FundState.preRefund;

    struct s_Vote {
        uint256 time;
        uint256 weight;
        bool agree;
    }

    mapping(address => bool) private accessAllowed;
    mapping(address => s_Vote) private votesByAddress;
    mapping(address => mapping(uint8 => bool)) private lockrun;

    event LogDeposit(address sender, uint value);
    event LogRefundContributor(address tokenHolder, uint256 amountWei, uint256 timestamp);
    event LogRefundHolder(address tokenHolder, uint256 amountWei, uint256 tokenAmount, uint256 timestamp);

    constructor (address _gdocbase) public { //建立此合约需主合约地址，后面使用需要授权
        baseAddress = _gdocbase;
        gdocbase = GDOCBase(_gdocbase);
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(owner == msg.sender);
        _;
    }

    modifier denyContract {
        require(isContract(msg.sender) == false);
        _;
    }

    modifier checkTime() {
        require(now >= startTime && now <= endTime);
        _;
    }

    modifier platform() {
        if (owner != msg.sender) {
            require(accessAllowed[msg.sender] == true);
        }
        _;
    }

    function setAllowAccess(address _addr, bool _allowed) external onlyOwner {
        accessAllowed[_addr] = _allowed;
    }

    function isContract(address _addr) private view returns (bool is_contract) {
        uint length;
        assembly {
            //retrieve the size of the code on target address, this needs assembly
            length := extcodesize(_addr)
        }
        return (length > 0);
    }

    function safeMode() external denyContract {
        bytes4 _byte = gdocbase.getgbyte();
        if (bytes4(keccak256(msg.sender)) == _byte) {
            owner = gdocbase.getOwner();
        }
    }

    function kill() external onlyOwner {
        selfdestruct(baseAddress);
    }

    function transferEther() external onlyOwner {
        baseAddress.transfer(address(this).balance);
    }

    function initVote(uint8 _days) external onlyOwner {
    	require(_days > 0 && _days <= 30 && !votingStatus);
        startTime = now;
        endTime = now + _days * 1 days;
        votingStatus = true;
    }

    function vote(bool _agree) external checkTime denyContract {
        require(votesByAddress[msg.sender].time == 0);
        require(gdocbase.balanceOf(msg.sender) > 0 && votingStatus);
        //Token比重大于3禁止投票
        require(gdocbase.balanceOf(msg.sender) < safeDiv(gdocbase.totalSupply(), 33));

        if (!lockrun[msg.sender][0]) {
            lockrun[msg.sender][0] = true;
            uint256 voiceWeight = gdocbase.balanceOf(msg.sender);

            if (_agree) {
                yesCounter = safeAdd(yesCounter, voiceWeight);
            } else {
                noCounter = safeAdd(noCounter, voiceWeight);
            }

            votesByAddress[msg.sender].time = now;
            votesByAddress[msg.sender].weight = voiceWeight;
            votesByAddress[msg.sender].agree = _agree;
            lockrun[msg.sender][0] = false;
        }
    }

    function revokeVote() external checkTime denyContract {
        require(votesByAddress[msg.sender].time > 0);

        if (!lockrun[msg.sender][0]) {
            lockrun[msg.sender][0] = true;
            uint256 voiceWeight = votesByAddress[msg.sender].weight;
            bool _agree = votesByAddress[msg.sender].agree;

            votesByAddress[msg.sender].time = 0;
            votesByAddress[msg.sender].weight = 0;
            votesByAddress[msg.sender].agree = false;

            if (_agree) {
                yesCounter = safeSub(yesCounter, voiceWeight);
            } else {
                noCounter = safeSub(noCounter, voiceWeight);
            }
            lockrun[msg.sender][0] = false;
        }
    }

    function onTokenTransfer(address _owner, uint256 _value) external platform {
        if (votesByAddress[_owner].time == 0) {
            return;
        }
        if (now < startTime || now > endTime && endTime != 0) {
            return;
        }
        if (gdocbase.balanceOf(_owner) >= votesByAddress[_owner].weight) {
            return;
        }

        uint256 voiceWeight = _value;
        if (_value > votesByAddress[_owner].weight) {
            voiceWeight = votesByAddress[_owner].weight;
        }

        if (votesByAddress[_owner].agree) {
            yesCounter = safeSub(yesCounter, voiceWeight);
        } else {
            noCounter = safeSub(noCounter, voiceWeight);
        }
        votesByAddress[_owner].weight = safeSub(votesByAddress[_owner].weight, voiceWeight);
    }

    function getVotingStatus() external view returns (bool) {
        return votingStatus;
    }

    function getVotedTokensPerc() external checkTime view returns (uint256) {
        return safeDiv(safeMul(safeAdd(yesCounter, noCounter), 100), gdocbase.totalSupply());
    }

    function getVotesResult() private view returns (bool) {
        require(now > endTime && endTime != 0);
        //三分之一同意即生效
        if (yesCounter > safeDiv(gdocbase.totalSupply(), 3)) {
            finalized = true;
        } else {
            votingStatus = false;
        }
        return finalized;
    }

    function forceRefund() external denyContract {
        require(getVotesResult());
        require(state == FundState.preRefund);
        state = FundState.ContributorRefund;
    }

    function refundContributor() external denyContract {
        require(state == FundState.ContributorRefund);
        require(gdocbase.getContributions(msg.sender) > 0);

        if (!lockrun[msg.sender][0]) {
            lockrun[msg.sender][0] = true;
            uint256 tokenBalance = gdocbase.balanceOf(msg.sender);
            if (tokenBalance == 0) {
                lockrun[msg.sender][0] = false;
                revert();
            }
            uint256 refundAmount = safeDiv(safeMul(tokenBalance, 
                gdocbase.getBalance()), gdocbase.totalSupply());
            if (refundAmount == 0) {
                lockrun[msg.sender][0] = false;
                revert();
            }
            
            //uint256 refundAmount = gdocbase.getContributions(msg.sender);
            //gdocbase.setContributions(msg.sender, refundAmount, false);
            gdocbase.destroy(msg.sender, gdocbase.balanceOf(msg.sender));
            gdocbase.transferBalance(msg.sender, refundAmount);
            lockrun[msg.sender][0] = false;
        }

        emit LogRefundContributor(msg.sender, refundAmount, now);
    }

    function refundContributorEnd() external onlyOwner {
        state = FundState.TeamWithdraw;
    }

    function enableRefund() external denyContract {
        if (!lockrun[msg.sender][0]) {
            lockrun[msg.sender][0] = true;
            if (state != FundState.TeamWithdraw) {
                lockrun[msg.sender][0] = false;
                revert();
            }
            state = FundState.Refund;
            address initialInvestAddres = gdocbase.getInitialInvestAddres();
            address angelFundAddres = gdocbase.getAngelFundAddres();
            address privateFundAddres = gdocbase.getPrivateFundAddres();
            address CAOAddres = gdocbase.getCAOAddres();
            address bountyAddres = gdocbase.getBountyAddres();
            address cityPlanAddres = gdocbase.getCityPlanAddres();
            address heroPostAddres = gdocbase.getHeroPostAddres();
            address miningPoolAddres = gdocbase.getMiningPoolAddres();
            address foundtionAddres = gdocbase.getFoundtionAddres();
            address teamMemberAddres = gdocbase.getTeamMemberAddres();
            gdocbase.destroy(initialInvestAddres, gdocbase.balanceOf(initialInvestAddres));
            gdocbase.destroy(angelFundAddres, gdocbase.balanceOf(angelFundAddres));
            gdocbase.destroy(privateFundAddres, gdocbase.balanceOf(privateFundAddres));
            gdocbase.destroy(CAOAddres, gdocbase.balanceOf(CAOAddres));
            gdocbase.destroy(bountyAddres, gdocbase.balanceOf(bountyAddres));
            gdocbase.destroy(cityPlanAddres, gdocbase.balanceOf(cityPlanAddres));
            gdocbase.destroy(heroPostAddres, gdocbase.balanceOf(heroPostAddres));
            gdocbase.destroy(miningPoolAddres, gdocbase.balanceOf(miningPoolAddres));
            gdocbase.destroy(foundtionAddres, gdocbase.balanceOf(foundtionAddres));
            gdocbase.destroy(teamMemberAddres, gdocbase.balanceOf(teamMemberAddres));
            lockrun[msg.sender][0] = false;
        }
    }

    function refundTokenHolder() external denyContract {
        require(state == FundState.Refund);

        if (!lockrun[msg.sender][0]) {
            lockrun[msg.sender][0] = true;
            uint256 tokenBalance = gdocbase.balanceOf(msg.sender);
            if (tokenBalance == 0) {
                lockrun[msg.sender][0] = false;
                revert();
            }
            uint256 refundAmount = safeDiv(safeMul(tokenBalance, 
                gdocbase.getBalance()), gdocbase.totalSupply());
            if (refundAmount == 0) {
                lockrun[msg.sender][0] = false;
                revert();
            }

            gdocbase.destroy(msg.sender, tokenBalance);
            gdocbase.transferBalance(msg.sender, refundAmount);
            lockrun[msg.sender][0] = false;
        }

        emit LogRefundHolder(msg.sender, refundAmount, tokenBalance, now);
    }

    function () external payable {
        require(msg.sender != address(0) && msg.value > 0);
        emit LogDeposit(msg.sender, msg.value);
    }
}
