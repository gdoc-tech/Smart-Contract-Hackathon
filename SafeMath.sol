pragma solidity ^0.4.23;


contract SafeMath {
    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);
        return c;
    }

    function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(a >= b);
        return a - b;
    }

    function safeMul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a * b;
        require(a == 0 || c / a == b);
        return c;
    }

    function safeDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0);
        uint256 c = a / b;
        return c;
    }
    
    function safeMod(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a % b;
        if (c == 0) return c;
        require((a + b) % c == ((a % c) + (b % c)) % c); //A % B = A - (A / B) * B
        return c;
    }
}
