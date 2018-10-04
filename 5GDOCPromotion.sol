pragma solidity ^0.4.23;

import './1GDOCBase.sol';
import './3GDOCToken.sol';

contract GDOCPromotion is SafeMath { //Promotion合约
    GDOCBase internal gdocbase;
    GDOCToken internal gdoctoken;

    address private owner;
    address private baseAddress;
    address private privateFundAddres;
    address private bountyAddres;
    address private cityPlanAddres;
    address private heroPostAddres;
    address private teamMemberAddres;
    uint256 private listedTime = 0;

    mapping(address => bool) private lockrun;

    event LogDeposit(address sender, uint value);

    constructor (address _gdocbase) public { //建立此合约需主合约地址，后面使用需要授权，还需Token合约授权
        baseAddress = _gdocbase;
        gdocbase = GDOCBase(_gdocbase);
        owner = msg.sender;
        privateFundAddres = gdocbase.getPrivateFundAddres();
        bountyAddres = gdocbase.getBountyAddres();
        cityPlanAddres = gdocbase.getCityPlanAddres();
        heroPostAddres = gdocbase.getHeroPostAddres();
        teamMemberAddres = gdocbase.getTeamMemberAddres();
    }

    modifier onlyOwner {
        require(owner == msg.sender);
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
        listedTime = gdoctoken.getListedTime();
    }

    function setPrivateFund(
        address _spender, 
        uint256 _tokens, 
        uint256 _ethers
    ) external onlyOwner {
        if (now < listedTime || listedTime == 0) {
            uint256 _value = safeMul(_tokens, (10 ** 18)); //自动计算比率，请注意输入参数
            require(gdocbase.balanceOf(privateFundAddres) >= _value);
            //从privateFund钱包转出Token
            bool _success = gdocbase.transfer(privateFundAddres, _spender, _value);
            if (_success) {
                gdocbase.setContributions(_spender, _ethers, true); //增加以太币贡献数量
                gdoctoken.addLockedTokens(_spender, 3, now, _value); //添加到Token锁定，用户组3
            }
        }
    }

    function setBounty(address _spender, uint256 _tokens) external onlyOwner {
        if (now < listedTime || listedTime == 0) {
            uint256 _value = safeMul(_tokens, (10 ** 18)); //自动计算比率，请注意输入参数
            require(gdocbase.balanceOf(bountyAddres) >= _value);
            //从bountyAddres钱包转出Token
            bool _success = gdocbase.transfer(bountyAddres, _spender, _value);
            if (_success) {
                gdoctoken.addLockedTokens(_spender, 5, now, _value); //添加到Token锁定，用户组5
            }
        }
    }
    
    function setCityPlan(address _spender, uint256 _tokens) external onlyOwner {
        if (now < listedTime || listedTime == 0) {
            uint256 _value = safeMul(_tokens, (10 ** 18)); //自动计算比率，请注意输入参数
            require(gdocbase.balanceOf(cityPlanAddres) >= _value);
            //从cityPlanAddres钱包转出Token
            bool _success = gdocbase.transfer(cityPlanAddres, _spender, _value);
            if (_success) {
                gdoctoken.addLockedTokens(_spender, 6, now, _value); //添加到Token锁定，用户组6
            }
        }
    }
    
    function setHeroPost(address _spender, uint256 _tokens) external onlyOwner {
        if (now < listedTime || listedTime == 0) {
            uint256 _value = safeMul(_tokens, (10 ** 18)); //自动计算比率，请注意输入参数
            require(gdocbase.balanceOf(heroPostAddres) >= _value);
            //从heroPostAddres钱包转出Token
            bool _success = gdocbase.transfer(heroPostAddres, _spender, _value);
            if (_success) {
                gdoctoken.addLockedTokens(_spender, 7, now, _value); //添加到Token锁定，用户组7
            }
        }
    }

    function setTeamMember(address _spender, uint256 _tokens) external onlyOwner {
        if (now < listedTime || listedTime == 0) {
            uint256 _value = safeMul(_tokens, (10 ** 18)); //自动计算比率，请注意输入参数
            require(gdocbase.balanceOf(teamMemberAddres) >= _value);
            //从teamMember钱包转出Token
            bool _success = gdocbase.transfer(teamMemberAddres, _spender, _value);
            if (_success) {
                gdoctoken.addLockedTokens(_spender, 10, now, _value); //添加到Token锁定，用户组10
            }
        }
    }

    function () external payable {
        require(msg.sender != address(0) && msg.value > 0);
        emit LogDeposit(msg.sender, msg.value);
    }
}
