pragma solidity ^0.4.23;

import './1GDOCBase.sol';
import './2GDOCReFund.sol';
import './3GDOCToken.sol';

contract GDOCTokenEx is SafeMath { //Token高级功能合约，一对多，多对多，代理转账等
    GDOCBase internal gdocbase;
    GDOCToken internal gdoctoken;
    GDOCReFund internal gdocrefund;

    address private owner;
    address private baseAddress;

    mapping(address => bool) private transferAllowed;
    mapping(address => uint256) private nonces;
    mapping(address => mapping(uint8 => bool)) private lockrun;

    event LogDeposit(address sender, uint value);

    constructor (address _gdocbase) public { //建立此合约需主合约地址，后面使用需要授权，还需Token合约/DAICO合约授权
        baseAddress = _gdocbase;
        gdocbase = GDOCBase(_gdocbase);
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(owner == msg.sender);
        _;
    }

    modifier proxyAllowed(address _addr) {
        require(transferAllowed[_addr] == true);
        _;
    }

    function setAllowProxy(address _addr, bool _allowed) external onlyOwner {
        transferAllowed[_addr] = _allowed;
    }

    modifier onlyPayloadSize(uint size) {
        require(msg.data.length >= size + 4);
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

    function setReFundAddress(address _gdocrefund) external onlyOwner {
        gdocrefund = GDOCReFund(_gdocrefund);
    }

    function getNonce(address _addr) external view returns (uint256) {
        return nonces[_addr];
    }

    function batchTransfer(
        address[] _receivers, 
        uint256 _value
    ) external onlyPayloadSize(2 * 32) returns (bool) {
        uint256 _count = _receivers.length;
        require(_count > 0 && _count <= 20);
        uint256 _amount = safeMul(_count, _value);
        require(_amount > 0 && gdocbase.balanceOf(msg.sender) >= _amount);
        require(gdoctoken.getChkLockedTokens(msg.sender, _amount));

        if (!lockrun[msg.sender][0]) {
            lockrun[msg.sender][0] = true;
            for (uint i = 0; i < _count; i++) {
                address _to = _receivers[i];
                bool _success = gdocbase.transfer(msg.sender, _to, _value);
                if (_success) {
                    if (gdoctoken.getLockedWalletAmount(msg.sender) > 0 
                        && !gdoctoken.getLockedWalletReleased(msg.sender) 
                        && gdoctoken.getLockedGroup(gdoctoken.getLockedWalletGroup(msg.sender)))
                    {
                        gdoctoken.setLockedWalletAmount(msg.sender, _value, false);
                    }
                    if (gdoctoken.getLockedWalletAmount(_to) > 0 
                        && !gdoctoken.getLockedWalletReleased(_to) 
                        && gdoctoken.getLockedGroup(gdoctoken.getLockedWalletGroup(_to)))
                    {
                        gdoctoken.setLockedWalletAmount(_to, _value, true);
                    }
                    if (gdocrefund.getVotingStatus()) {
                        gdocrefund.onTokenTransfer(msg.sender, _value);
                    }
                }
            }
            lockrun[msg.sender][0] = false;
        }
        return true;
    }

    function batchTransfers(
        address[] _receivers, 
        uint256[] _values
    ) external onlyPayloadSize(2 * 32) returns (bool) {
        require(_receivers.length == _values.length);
        uint256 _count = _receivers.length;
        require(_count > 0 && _count <= 20);
        uint256 _amount = 0;
        for (uint256 i = 0; i < _values.length; i++) _amount = safeAdd(_amount, _values[i]);
        require(_amount > 0 && gdocbase.balanceOf(msg.sender) >= _amount);
        require(gdoctoken.getChkLockedTokens(msg.sender, _amount));

        if (!lockrun[msg.sender][0]) {
            lockrun[msg.sender][0] = true;
            for (uint j = 0; j < _count; j++) {
                address _to = _receivers[j];
                uint256 _value = _values[j];
                bool _success = gdocbase.transfer(msg.sender, _to, _value);
                if (_success) {
                    if (gdoctoken.getLockedWalletAmount(msg.sender) > 0 
                        && !gdoctoken.getLockedWalletReleased(msg.sender) 
                        && gdoctoken.getLockedGroup(gdoctoken.getLockedWalletGroup(msg.sender)))
                    {
                        gdoctoken.setLockedWalletAmount(msg.sender, _value, false);
                    }
                    if (gdoctoken.getLockedWalletAmount(_to) > 0 
                        && !gdoctoken.getLockedWalletReleased(_to) 
                        && gdoctoken.getLockedGroup(gdoctoken.getLockedWalletGroup(_to)))
                    {
                        gdoctoken.setLockedWalletAmount(_to, _value, true);
                    }
                    if (gdocrefund.getVotingStatus()) {
                        gdocrefund.onTokenTransfer(msg.sender, _value);
                    }
                }
            }
            lockrun[msg.sender][0] = false;
        }
        return true;
    }

    function transferProxy(address _from, address _to, uint256 _value, uint256 _feeToken,
        uint8 _v, bytes32 _r, bytes32 _s) external proxyAllowed(_from) returns (bool) {
        require(_to != address(0));
        require(gdocbase.balanceOf(_from) >= _feeToken + _value && _feeToken < _feeToken + _value);
        require(_feeToken < _value && _value - _feeToken > _feeToken);
        require(gdoctoken.getChkLockedTokens(_from, _value + _feeToken));

        bool _success = false;
        if (!lockrun[msg.sender][0]) {
            lockrun[msg.sender][0] = true;
            uint256 _nonce = nonces[_from];
            bytes32 _h = keccak256(_from, _to, _value, _feeToken, _nonce, address(this));
            if (_from != ecrecover(_h, _v, _r, _s)) {
                lockrun[msg.sender][0] = false;
                revert();
            }
            if (gdocbase.transfer(_from, _to, _value) == true 
                && gdocbase.transfer(_from, msg.sender, _feeToken) == true) _success = true;
            if (_success) {
                if (gdoctoken.getLockedWalletAmount(_from) > 0 
                    && !gdoctoken.getLockedWalletReleased(_from) 
                    && gdoctoken.getLockedGroup(gdoctoken.getLockedWalletGroup(_from)))
                {
                    gdoctoken.setLockedWalletAmount(_from, _value, false);
                }
                if (gdoctoken.getLockedWalletAmount(_to) > 0 
                    && !gdoctoken.getLockedWalletReleased(_to) 
                    && gdoctoken.getLockedGroup(gdoctoken.getLockedWalletGroup(_to)))
                {
                    gdoctoken.setLockedWalletAmount(_to, _value, true);
                }
                if (gdocrefund.getVotingStatus()) {
                    gdocrefund.onTokenTransfer(_from, _value);
                }
                nonces[_from] = _nonce + 1;
            }
            lockrun[msg.sender][0] = false;
        }
        return _success;
    }

    function approveProxy(address _from, address _spender, uint256 _value,
        uint8 _v, bytes32 _r, bytes32 _s) external returns (bool) {
        require(_from != _spender && _spender != address(0));
        require(gdocbase.balanceOf(_from) >= _value && _value > 0);
        require(gdoctoken.getChkLockedTokens(_from, _value));

       bool _success = false;
        if (!lockrun[msg.sender][0]) {
            lockrun[msg.sender][0] = true;
            uint256 _nonce = nonces[_from];
            bytes32 _h = keccak256(_from, _spender, _value, _nonce, address(this));
            if (_from != ecrecover(_h, _v, _r, _s)) {
                lockrun[msg.sender][0] = false;
                revert();
            }
            _success = gdocbase.approve(_from, _spender, _value);
            if (_success) nonces[_from] = _nonce + 1;
            lockrun[msg.sender][0] = false;
        }
        return _success;
    }

    function () external payable {
        require(msg.sender != address(0) && msg.value > 0);
        emit LogDeposit(msg.sender, msg.value);
    }
}
