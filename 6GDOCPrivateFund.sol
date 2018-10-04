pragma solidity ^0.4.23;

import './1GDOCBase.sol';
import './3GDOCToken.sol';

contract GDOCPrivateFund is SafeMath, DateTime { //私募合约
    GDOCBase internal gdocbase;
    GDOCToken internal gdoctoken;

    address private owner;
    address private baseAddress;
    address private privateFundAddres;

    mapping(address => bool) private whiteList;
    mapping(address => bool) private lockrun;

    uint256 private privateFundStart = 1530288000 + 28800; //私募开始时间2018.06.30
    uint256 private privateFundEnd = 1532880000 + 28800; //私募结束时间2018.07.30
    uint256 private constant privateFundMin = 10 ether; //私募最低要求
    uint256 private constant privateFundMax = 5000 ether; //私募最高要求
    uint256 private constant privateFundRatio = 560000; //私募兑换比率

    constructor (address _gdocbase) public { //建立此合约需主合约地址，后面使用需要授权，还需Token合约授权
        baseAddress = _gdocbase;
        gdocbase = GDOCBase(_gdocbase);
        owner = msg.sender;
        privateFundAddres = gdocbase.getPrivateFundAddres();
    }

    modifier onlyOwner {
        require(owner == msg.sender);
        _;
    }

    modifier onlyWhitelist() {
        require(whiteList[msg.sender] == true);
        _;
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

    function setPrivateFundStart(
        uint16 _year, 
        uint8 _month, 
        uint8 _day, 
        uint8 _hour, 
        uint8 _minute, 
        uint8 _second
    ) external onlyOwner {
        privateFundStart = toTimestamp(_year, _month, _day, _hour, _minute, _second);
    }

    function setPrivateFundEnd(
        uint16 _year, 
        uint8 _month, 
        uint8 _day, 
        uint8 _hour, 
        uint8 _minute, 
        uint8 _second
    ) external onlyOwner {
        privateFundEnd = toTimestamp(_year, _month, _day, _hour, _minute, _second);
    }

    function isWhitelist(address _spender) external view onlyOwner returns (bool) {
        return whiteList[_spender];
    }

    function addWhitelist(address _spender) external onlyOwner {
        whiteList[_spender] = true;
    }

    function addWhitelists(address[] _spender) external onlyOwner {
        for (uint256 i = 0; i < _spender.length; i++) {
            whiteList[_spender[i]] = true;
        }
    }

    function delWhitelist(address _spender) external onlyOwner {
        delete whiteList[_spender];
    }

    function delWhitelists(address[] _spender) external onlyOwner {
        for (uint256 i = 0; i < _spender.length; i++) {
            delete whiteList[_spender[i]];
        }
    }

    function () external payable onlyWhitelist {
        require(msg.sender != address(0) && msg.value > 0);

        if (now <= privateFundStart || now >= privateFundEnd) { //私募阶段
            revert();
        }

        if (!lockrun[msg.sender]) {

            lockrun[msg.sender] = true;
            address _sender = msg.sender;
            uint256 _amount = msg.value;
            uint256 _tokens = safeMul(_amount, privateFundRatio);

            if (_amount < privateFundMin 
                || _amount > privateFundMax 
                || gdocbase.balanceOf(privateFundAddres) < _tokens)
            { //私募限额/Token不足
                lockrun[msg.sender] = false;
                revert();
            }

            //从privateFund钱包转出Token
            bool _success = gdocbase.transfer(privateFundAddres, _sender, _tokens);
            if (!_success) {
                lockrun[msg.sender] = false;
                revert();
            }
            gdocbase.setContributions(_sender, _amount, true); //增加以太币贡献数量
            gdoctoken.addLockedTokens(_sender, 3, now, _tokens); //添加到Token锁定，用户组3
            lockrun[msg.sender] = false;
        } 
    }
}
