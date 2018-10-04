pragma solidity ^0.4.23;

import './1GDOCBase.sol';
import './3GDOCToken.sol';

contract GDOCCAO is SafeMath, DateTime { //CAO合约
    GDOCBase internal gdocbase;
    GDOCToken internal gdoctoken;

    address private owner;
    address private baseAddress;
    bool private denyContract = true;
    bool private votingStatus = false;
    uint256 private startTime;
    uint256 private endTime;
    address private CAOAddres;
    uint256 private CAOTotal = 0;
    uint256 private CAORound = 0;
    uint256 private CAOStart = 0;
    uint256 private CAOEnd = 0;
    uint256 private CAOMin = 0;
    uint256 private CAOMax = 0;
    uint256 private CAORatio = 0;
    uint256 private CAOAmount = 0;

    struct s_Count {
        uint256 yesCounter;
        uint256 noCounter;
    }

    struct s_Vote {
        uint256 time;
        uint256 weight;
        uint8 option;
        bool agree;
    }

    uint256[] private Ratio;
    uint256[] private Amount;
    mapping(address => s_Vote) private votesAmount;
    mapping(address => s_Vote) private votesRatio;
    mapping(uint256 => s_Count) private amountCounter;
    mapping(uint256 => s_Count) private ratioCounter;
    mapping(address => bool) private accessAllowed;
    mapping(address => bool) private lockrun;

    constructor (address _gdocbase) public { //建立此合约需主合约地址，后面使用需要授权，还需Token合约授权
        baseAddress = _gdocbase;
        gdocbase = GDOCBase(_gdocbase);
        owner = msg.sender;
        CAOAddres = gdocbase.getCAOAddres();
    }

    modifier onlyOwner {
        require(owner == msg.sender);
        _;
    }

    modifier platform() {
        if (isContract(msg.sender) && denyContract) {
            require(accessAllowed[msg.sender] == true);
        }
        _;
    }

    modifier checkTime() {
        require(now >= startTime && now <= endTime);
        _;
    }

    function setDenyContract(bool _deny) external onlyOwner {
        denyContract = _deny;
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

    function safeMode() external {
        require(isContract(msg.sender) == false);

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

    function setTokenAddress(address _gdoctoken) external onlyOwner {
        gdoctoken = GDOCToken(_gdoctoken);
    }

    function setCAO(
        uint256 _CAOStart, 
        uint256 _CAOEnd, 
        uint256 _CAOMin, 
        uint256 _CAOMax, 
        uint256 _CAORatio, 
        uint256 _CAOAmount
    ) external onlyOwner {
        if (_CAOStart == 0
            || _CAOEnd <= _CAOStart 
            || _CAOMin == 0
            || _CAOMax == 0
            || _CAORatio == 0
            || _CAOAmount == 0)
        {
            revert();
        }
        CAOStart = _CAOStart;
        CAOEnd = _CAOEnd;
        CAOMin = _CAOMin;
        CAOMax = _CAOMax;
        CAORatio = _CAORatio;
        CAOAmount = _CAOAmount;
        CAOTotal = 0;//总量置零
    }

    function setCAORatio(uint256[] _ratio) external onlyOwner {
        require(_ratio.length == 5 && Ratio.length == 0);
        Ratio = _ratio;
    }

    function setCAOAmount(uint256[] _amount) external onlyOwner {
        require(_amount.length == 5 && Amount.length == 0);
        Amount = _amount;
    }

    function getCAORatio() external checkTime view returns(
        uint256 Round, 
        uint256 Ratio1, 
        uint256 Ratio2, 
        uint256 Ratio3, 
        uint256 Ratio4, 
        uint256 Ratio5)
    {
        require(Ratio.length == 5 && CAORound > 0);
        return(CAORound, Ratio[0], Ratio[1], Ratio[2], Ratio[3], Ratio[4]);
    }

    function getCAOAmount() external checkTime view returns(
        uint256 Round, 
        uint256 Amount1, 
        uint256 Amount2, 
        uint256 Amount3, 
        uint256 Amount4, 
        uint256 Amount5)
    {
        require(Amount.length == 5 && CAORound > 0);
        return(CAORound, Amount[0], Amount[1], Amount[2], Amount[3], Amount[4]);
    }

    function getTimestamp(
        uint16 _year, 
        uint8 _month, 
        uint8 _day, 
        uint8 _hour, 
        uint8 _minute, 
        uint8 _second) external pure returns(uint256)
    {
        return toTimestamp(_year, _month, _day, _hour, _minute, _second);
    }

    function getTimestring(uint _timestamp) external pure returns (
        uint16 Year, uint8 Month, uint8 Day, uint8 Hour, uint8 Minute, uint8 Second) {
        return (getYear(_timestamp), getMonth(_timestamp), getDay(_timestamp), 
            getHour(_timestamp), getMinute(_timestamp), getSecond(_timestamp));
    }

    function initVote(uint8 _days) external onlyOwner {
        require(_days > 0 && _days <= 30 && !votingStatus);
        require(Ratio.length == 5 && Amount.length == 5);
        CAORound++;
        startTime = now;
        endTime = now + _days * 1 days;
        votingStatus = true;
    }

    function closeVote() external onlyOwner {
        require(now > endTime && endTime != 0);
        delete Ratio;
        delete Amount;
        votingStatus = false;
    }

    function ratioVote(bool _agree, uint8 _option) external checkTime platform {
        require(_option > 0 && _option < 6);
        require(Ratio.length == 5 && CAORound > 0);
        require(votesRatio[msg.sender].time == 0);
        require(gdocbase.balanceOf(msg.sender) > 0 && votingStatus);
        //Token比重大于3禁止投票
        require(gdocbase.balanceOf(msg.sender) < safeDiv(gdocbase.totalSupply(), 33));

        if (!lockrun[msg.sender]) {
            lockrun[msg.sender] = true;
            uint256 voiceWeight = gdocbase.balanceOf(msg.sender);

            if (_agree) {
                ratioCounter[_option - 1].yesCounter = safeAdd(ratioCounter[_option - 1].yesCounter, 
                    voiceWeight);
            } else {
                ratioCounter[_option - 1].noCounter = safeAdd(ratioCounter[_option - 1].noCounter, 
                    voiceWeight);
            }

            votesRatio[msg.sender].time = now;
            votesRatio[msg.sender].weight = voiceWeight;
            votesRatio[msg.sender].option = _option;
            votesRatio[msg.sender].agree = _agree;
            lockrun[msg.sender] = false;
        }
    }

    function revokeRatioVote(uint8 _option) external checkTime platform {
        require(_option > 0 && _option < 6);
        require(votesRatio[msg.sender].option > 0 
            && votesRatio[msg.sender].option < 6);
        require(Ratio.length == 5 && CAORound > 0);
        require(votesRatio[msg.sender].time > 0);

        if (!lockrun[msg.sender]) {
            lockrun[msg.sender] = true;
            uint256 voiceWeight = votesRatio[msg.sender].weight;
            bool _agree = votesRatio[msg.sender].agree;

            votesRatio[msg.sender].time = 0;
            votesRatio[msg.sender].weight = 0;
            votesRatio[msg.sender].option = 6;
            votesRatio[msg.sender].agree = false;

            if (_agree) {
                ratioCounter[_option - 1].yesCounter = safeSub(ratioCounter[_option - 1].yesCounter, 
                    voiceWeight);
            } else {
                ratioCounter[_option - 1].noCounter = safeSub(ratioCounter[_option - 1].noCounter, 
                    voiceWeight);
            }
            lockrun[msg.sender] = false;
        }
    }

    function amountVote(bool _agree, uint8 _option) external checkTime platform {
        require(_option > 0 && _option < 6);
        require(Amount.length == 5 && CAORound > 0);
        require(votesAmount[msg.sender].time == 0);
        require(gdocbase.balanceOf(msg.sender) > 0 && votingStatus);
        //Token比重大于3禁止投票
        require(gdocbase.balanceOf(msg.sender) < safeDiv(gdocbase.totalSupply(), 33));

        if (!lockrun[msg.sender]) {
            lockrun[msg.sender] = true;
            uint256 voiceWeight = gdocbase.balanceOf(msg.sender);

            if (_agree) {
                amountCounter[_option - 1].yesCounter = safeAdd(amountCounter[_option - 1].yesCounter, 
                    voiceWeight);
            } else {
                amountCounter[_option - 1].noCounter = safeAdd(amountCounter[_option - 1].noCounter, 
                    voiceWeight);
            }

            votesAmount[msg.sender].time = now;
            votesAmount[msg.sender].weight = voiceWeight;
            votesAmount[msg.sender].option = _option;
            votesAmount[msg.sender].agree = _agree;
            lockrun[msg.sender] = false;
        }
    }

    function revokeAmountVote(uint8 _option) external checkTime platform {
        require(_option > 0 && _option < 6);
        require(votesAmount[msg.sender].option > 0 
            && votesAmount[msg.sender].option < 6);
        require(Amount.length == 5 && CAORound > 0);
        require(votesAmount[msg.sender].time > 0);

        if (!lockrun[msg.sender]) {
            lockrun[msg.sender] = true;
            uint256 voiceWeight = votesAmount[msg.sender].weight;
            bool _agree = votesAmount[msg.sender].agree;

            votesAmount[msg.sender].time = 0;
            votesAmount[msg.sender].weight = 0;
            votesAmount[msg.sender].option = 6;
            votesAmount[msg.sender].agree = false;

            if (_agree) {
                amountCounter[_option - 1].yesCounter = safeSub(amountCounter[_option - 1].yesCounter, 
                    voiceWeight);
            } else {
                amountCounter[_option - 1].noCounter = safeSub(amountCounter[_option - 1].noCounter, 
                    voiceWeight);
            }
            lockrun[msg.sender] = false;
        }
    }

    function getVotesResult() external view platform returns 
    (uint256 Round, uint256 finalizedRatio, uint256 finalizedAmout) {
        require(now > endTime && endTime != 0 && !votingStatus);
        uint256 _ratioyes = 0;
        uint256 _rationo = 0;
        uint256 _ratioweight = 0;
        uint256 _amountyes = 0;
        uint256 _amountno = 0;
        uint256 _amountweight = 0;
        uint256 ratio = 0;
        uint256 amount = 0;
        uint256 i = 0;
        for(i = 0; i < 5; i++) {
            _ratioyes = safeAdd(_ratioyes, ratioCounter[i].yesCounter);
            _rationo = safeAdd(_rationo, ratioCounter[i].noCounter);
        }
        for(i = 0; i < 5; i++) {
            _amountyes = safeAdd(_amountyes, amountCounter[i].yesCounter);
            _amountno = safeAdd(_amountno, amountCounter[i].noCounter);
        }
        _ratioweight = safeMul(safeDiv(ratioCounter[0].yesCounter, (10 ** 18)), Ratio[0]);
        _ratioweight = safeAdd(_ratioweight, 
            safeMul(safeDiv(ratioCounter[1].yesCounter, (10 ** 18)), Ratio[1]));
        _ratioweight = safeAdd(_ratioweight, 
            safeMul(safeDiv(ratioCounter[2].yesCounter, (10 ** 18)), Ratio[2]));
        _ratioweight = safeAdd(_ratioweight, 
            safeMul(safeDiv(ratioCounter[3].yesCounter, (10 ** 18)), Ratio[3]));
        _ratioweight = safeAdd(_ratioweight, 
            safeMul(safeDiv(ratioCounter[4].yesCounter, (10 ** 18)), Ratio[4]));

        //ratio按加权平均计算
        ratio = safeDiv(_ratioweight, safeDiv(_ratioyes, (10 ** 18)));
        
        //amount默认三分之二同意即生效，否则按加权平均计算
        for(i = 0; i < 5; i++) {
            if (amountCounter[i].yesCounter > safeMul(safeDiv(safeAdd(_amountyes, _amountno), 3), 2)) {
                amount = Amount[i];
                break;
            }
        }
        if (amount == 0) {
            _amountweight = safeMul(safeDiv(amountCounter[0].yesCounter, (10 ** 18)), Amount[0]);
            _amountweight = safeAdd(_amountweight, 
                safeMul(safeDiv(amountCounter[1].yesCounter, (10 ** 18)), Amount[1]));
            _amountweight = safeAdd(_amountweight, 
                safeMul(safeDiv(amountCounter[2].yesCounter, (10 ** 18)), Amount[2]));
            _amountweight = safeAdd(_amountweight, 
                safeMul(safeDiv(amountCounter[3].yesCounter, (10 ** 18)), Amount[3]));
            _amountweight = safeAdd(_amountweight, 
                safeMul(safeDiv(amountCounter[4].yesCounter, (10 ** 18)), Amount[4]));
            amount = safeDiv(_amountweight, safeDiv(_amountyes, (10 ** 18)));
        }
        return (CAORound, ratio, amount);
    }

    function () external payable platform {
        require(now > endTime && endTime != 0);
        require(msg.sender != address(0) && msg.value > 0);
        if (now <= CAOStart || now >= CAOEnd) { //CAO阶段
            revert();
        }

        if (!lockrun[msg.sender]) {

            lockrun[msg.sender] = true;
            address _sender = msg.sender;
            uint256 _amount = msg.value;
            uint256 _tokens = safeMul(_amount, CAORatio);
            CAOTotal = safeAdd(CAOTotal, _tokens);

            if (_amount < CAOMin 
                || _amount > CAOMax 
                || gdocbase.balanceOf(CAOAddres) < _tokens
                || CAOTotal >= CAOAmount)
            { //CAO限额/Token不足/超过此轮发行量
                lockrun[msg.sender] = false;
                revert();
            }

            //从CAO钱包转出Token
            bool _success = gdocbase.transfer(CAOAddres, _sender, _tokens);
            if (!_success) {
                lockrun[msg.sender] = false;
                revert();
            }

            gdocbase.setContributions(_sender, _amount, true); //增加以太币贡献数量
            gdoctoken.addLockedTokens(_sender, 4, now, _tokens); //添加到Token锁定，用户组4
            lockrun[msg.sender] = false;
        } 
    }
}
