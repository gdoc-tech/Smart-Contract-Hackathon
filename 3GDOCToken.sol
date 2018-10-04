pragma solidity ^0.4.23;

import './1GDOCBase.sol';
import './2GDOCReFund.sol';

contract GDOCToken is SafeMath, DateTime { //Token功能合约
    GDOCBase internal gdocbase;
    GDOCReFund internal gdocrefund;

    address private owner;
    address private baseAddress;
    uint256 private listedTime = 0;

    mapping(address => bool) private accessAllowed;
    mapping(address => mapping(uint8 => bool)) private lockrun;

    struct s_LockedTokens {
        uint256 amount;
        uint8 userGroup;
        uint256 allowAmount;
        uint256 quarterlyAmount;
        uint256 lastAmount;
        uint256 lockStartTime;
        uint256 lockEndTime;
        bool released;
    }

    mapping(address => s_LockedTokens) private lockedTokens;
    mapping(uint8 => bool) private lockedGroup;

    string public name;
    string public symbol;
    uint8 public decimals;

    event LogDeposit(address sender, uint value);

    constructor (address _gdocbase) public { //建立此合约需主合约地址，后面使用需要授权，还需DAICO合约授权
        symbol = "GDOT";
        name = "GDOT";
        decimals = 18;
        baseAddress = _gdocbase;
        gdocbase = GDOCBase(_gdocbase);
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(owner == msg.sender);
        _;
    }

    modifier platform() {
        if (owner != msg.sender) {
            require(accessAllowed[msg.sender] == true);
        }
        _;
    }

    modifier onlyPayloadSize(uint size) {
        require(msg.data.length >= size + 4);
        _;
    }

    function setAllowAccess(address _addr, bool _allowed) external onlyOwner {
        accessAllowed[_addr] = _allowed;
    }

    function setLockedGroup(uint8 _group, bool _released) external onlyOwner {
        lockedGroup[_group] = _released;
    }

    function setLockedWalletReleased(address _addr, bool _released) external onlyOwner {
        require(lockedTokens[_addr].amount > 0);
        lockedTokens[_addr].released = _released;
    }

    function setLockedWalletAmount(
        address _addr, 
        uint256 _value, 
        bool _addorsub
    ) external platform {
        if (_addorsub) {
            lockedTokens[_addr].allowAmount = safeAdd(lockedTokens[_addr].allowAmount, _value);
        } else {
            lockedTokens[_addr].allowAmount = safeSub(lockedTokens[_addr].allowAmount, _value);
        }   
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

    function setReFundAddress(address _gdocrefund) external onlyOwner {
        gdocrefund = GDOCReFund(_gdocrefund);
    }

    function setListedTime(uint256 _time) external onlyOwner {
        if (listedTime == 0) {
            listedTime = _time;
        }
    }

    function getLockedWalletGroup(address _addr) external view returns (uint8) {
        return lockedTokens[_addr].userGroup;
    }

    function getLockedWalletReleased(address _addr) external view returns (bool) {
        return lockedTokens[_addr].released;
    }

    function getLockedWalletAmount(address _addr) external view returns (uint256) {
        return lockedTokens[_addr].amount;
    }

    function getLockedGroup(uint8 _group) external view returns (bool) {
        return lockedGroup[_group];
    }

    function getListedTime() external view returns (uint256) {
        return listedTime;
    }

    function getChkLockedTokens(
        address _owner, 
        uint256 _value
    ) external platform returns (bool) {
        return chkLockedTokens(_owner, _value);
    }

    function addLockedTokens(
        address _owner, 
        uint8 _userGroup, 
        uint256 _lockStartTime, 
        uint256 _value
    ) external platform {
        lockedTokens[_owner].userGroup = _userGroup;
        lockedTokens[_owner].lockStartTime = _lockStartTime;
        lockedTokens[_owner].lockEndTime = _lockStartTime + 731 days; //锁定两年
        lockedTokens[_owner].amount = safeAdd(lockedTokens[_owner].amount, _value);

        uint256 _amountTotal = lockedTokens[_owner].amount;
        uint256 _amount = safeDiv(_amountTotal, 10); //首次解禁10%
        if (_amount == 0) _amount = _amountTotal;
        lockedTokens[_owner].allowAmount = _amount;
        uint256 _amountLeft = safeSub(_amountTotal, _amount);

        lockedTokens[_owner].quarterlyAmount = safeDiv(_amountLeft, 8);
        lockedTokens[_owner].lastAmount = safeAdd(lockedTokens[_owner].quarterlyAmount, 
            safeMod(_amountLeft, 8));
    }

    function chkLockedTokens(address _owner, uint256 _value) private returns (bool) {
        if (lockedTokens[_owner].amount > 0 
            && !lockedTokens[_owner].released 
            && lockedGroup[lockedTokens[_owner].userGroup])
        {       
            uint256 _time = now;
            if (_time > lockedTokens[_owner].lockEndTime) {
                lockedTokens[_owner].released = true;
                return true;
            }

            uint256 _startTime = lockedTokens[_owner].lockStartTime;

            if (safeSub(getYear(_time), getYear(_startTime)) == 0 
                && getSeason(_time) - getSeason(_startTime) > 0)
            {
                lockedTokens[_owner].allowAmount = safeAdd(lockedTokens[_owner].allowAmount, 
                    safeMul(lockedTokens[_owner].quarterlyAmount, 
                        getSeason(_time) - getSeason(_startTime)));
            }

            if (safeSub(getYear(_time), getYear(_startTime)) == 1)
            {
                lockedTokens[_owner].allowAmount = safeAdd(lockedTokens[_owner].allowAmount, 
                    safeMul(lockedTokens[_owner].quarterlyAmount, 
                        4 + getSeason(_time) - getSeason(_startTime)));
            }

            if (safeSub(getYear(_time), getYear(_startTime)) > 1) {
                if (safeSub(getSeason(_time), getSeason(lockedTokens[_owner].lockEndTime)) == 0)
                {
                    uint256 _amount = safeAdd(safeMul(lockedTokens[_owner].quarterlyAmount, 
                        7 + getSeason(_time) - getSeason(_startTime)), 
                    lockedTokens[_owner].lastAmount);
                    lockedTokens[_owner].allowAmount = safeAdd(lockedTokens[_owner].allowAmount, 
                        _amount);
                } 
                else 
                {
                    lockedTokens[_owner].allowAmount = safeAdd(lockedTokens[_owner].allowAmount, 
                        safeMul(lockedTokens[_owner].quarterlyAmount, 
                            8 + getSeason(_time) - getSeason(_startTime)));
                }
            }

            lockedTokens[_owner].lockStartTime = _time;

            if (lockedTokens[_owner].allowAmount < _value) {
                return false;
            }
        }
        return true;
    }

    function totalSupply() external view returns (uint256) {
        return gdocbase.totalSupply();
    }

    function balanceOf(address _owner) external view returns (uint256) {
        return gdocbase.balanceOf(_owner);
    }

    function allowance(address _owner, address _spender) external view returns (uint256) {
        return gdocbase.allowance(_owner, _spender);
    }

    function transfer(
        address _to, 
        uint256 _value
    ) external onlyPayloadSize(2 * 32) returns (bool) {
        require(_to != address(0));
        require(gdocbase.balanceOf(msg.sender) >= _value);
        require(chkLockedTokens(msg.sender, _value)); //Token解禁机制

        bool _success = false;
        if (!lockrun[msg.sender][0]) {
            lockrun[msg.sender][0] = true;
            _success = gdocbase.transfer(msg.sender, _to, _value);
            if (_success) {
                if (lockedTokens[msg.sender].amount > 0 
                    && !lockedTokens[msg.sender].released 
                    && lockedGroup[lockedTokens[msg.sender].userGroup])
                {
                    lockedTokens[msg.sender].allowAmount = safeSub(lockedTokens[msg.sender].allowAmount, 
                        _value);
                }
                if (lockedTokens[_to].amount > 0 
                    && !lockedTokens[_to].released 
                    && lockedGroup[lockedTokens[_to].userGroup])
                {
                    lockedTokens[_to].allowAmount = safeAdd(lockedTokens[_to].allowAmount, _value);
                }
                if (gdocrefund.getVotingStatus()) {
                    gdocrefund.onTokenTransfer(msg.sender, _value);
                }
            }
            lockrun[msg.sender][0] = false;
        }
        return _success;
    }

    function transferFrom(
        address _from, 
        address _to, 
        uint256 _value
    ) external onlyPayloadSize(2 * 32) returns (bool) {
        require(_to != address(0));
        require(gdocbase.balanceOf(_from) >= _value 
            && gdocbase.allowance(_from, msg.sender) >= _value);
        require(chkLockedTokens(_from, _value));

        bool _success = false;
        if (!lockrun[msg.sender][0]) {
            lockrun[msg.sender][0] = true;
            _success = gdocbase.transferFrom(msg.sender, _from, _to, _value);
            if (_success) {
                if (lockedTokens[_from].amount > 0 
                    && !lockedTokens[_from].released 
                    && lockedGroup[lockedTokens[_from].userGroup])
                {
                    lockedTokens[_from].allowAmount = safeSub(lockedTokens[_from].allowAmount, _value);
                }
                if (lockedTokens[_to].amount > 0 
                    && !lockedTokens[_to].released 
                    && lockedGroup[lockedTokens[_to].userGroup])
                {
                    lockedTokens[_to].allowAmount = safeAdd(lockedTokens[_to].allowAmount, _value);
                }
                if (gdocrefund.getVotingStatus()) {
                    gdocrefund.onTokenTransfer(_from, _value);
                }
            }
            lockrun[msg.sender][0] = false;
        }
        return _success;
    }

    function approve(address _spender, uint256 _value) external returns (bool) {
        require(msg.sender != _spender && _spender != address(0));
        require(gdocbase.balanceOf(msg.sender) >= _value && _value > 0);
        require(chkLockedTokens(msg.sender, _value));

        bool _success = false;
        if (!lockrun[msg.sender][0]) {
            lockrun[msg.sender][0] = true;
            _success = gdocbase.approve(msg.sender, _spender, _value);
            lockrun[msg.sender][0] = false;
        }
        return _success;
    }

    function () external payable {
        require(msg.sender != address(0) && msg.value > 0);
        emit LogDeposit(msg.sender, msg.value);
    }
}
