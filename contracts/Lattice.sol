// SPDX-License-Identifier: GNU GPLv3

pragma solidity 0.8.17;

import "./ERC20.sol";
import "./Ownable.sol";

import "./SafeMath.sol";

import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";

contract Lattice is ERC20, Ownable {
    using SafeMath for uint256;

    address public developmentWallet;
    address public marketingWallet;

    /// @dev buyFee -> Development wallet
    /// @dev sellFee[0] -> Development Wallet and sellFee[1] -> Marketing Wallet
    uint256 public buyFee;
    uint256[2] public sellFee;

    uint256 public buyLockTime;
    uint256 public sellLockTime;

    uint256 public limitTime;
    uint256 public buyLimitPercentage;
    uint256 public sellLimitPercentage;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    struct Limit {
        address account;
        uint256 amount;
        uint256 startTime;
    }

    // internal storage

    // for pausing consecutive buys/sells
    mapping (address => uint256) public getBuyTimeLock;
    mapping (address => uint256) public getSellTimeLock;

    // for limiting bulk buying/selling
    mapping (address => Limit) public getBuyLimits;
    mapping (address => Limit) public getSellLimits;

    // blacklisted from sending and recieving transactions
    mapping (address => bool) private _isBlacklisted;

    // excluded from buying/sellimg limit
    mapping (address => bool) private _isExcludedFromLimit;

    // exlcuded from fees and max transaction amount
    mapping (address => bool) private _isExcludedFromFees;

    // LP pairs, could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;

    // events

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    event BlackListAddress(address indexed account, bool isBlackListed);

    event BlackListMultipleAddresses(address[] accounts, bool isExcluded);

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);

    event ExcludeFromLimit(address indexed account, bool isExcluded);

    event ExcludeMultipleAccountsFromLimit(address[] accounts, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed state);

    constructor() ERC20("The Lattice", "LATI") {
        developmentWallet = 0xC6c7a0659C5e3AE8a8a305FfD0aEf1827D3C49B1;
        marketingWallet = 0x8dB24737563e5b5cFcc9DCEd6439De0D56d53c7D;

        buyFee = 20;
        sellFee = [10, 20];

        buyLockTime = 5 minutes;
        sellLockTime = 5 minutes;

        limitTime = 1 days;
        buyLimitPercentage = 100;
        sellLimitPercentage = 100;

        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

        // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());

        setAutomatedMarketMakerPair(uniswapV2Pair, true);

        address newOwner = 0x3d27d7106f7202ecfF115834EBa72C034E912703;

        // exclude from paying fees
        excludeFromFees(newOwner, true);
        excludeFromFees(address(this), true);

        // exclude from buy/sell limit and time locks
        excludeFromLimit(newOwner, true);
        excludeFromLimit(address(this), true);

        _mint(newOwner, 25_000_000 * (10 ** 18));

        _transferOwnership(newOwner);
    }

    function updateDevelopmentWallet(address newDevelopmentWallet) external onlyOwner {
        require(developmentWallet != newDevelopmentWallet, "Lattice: Treasury Wallet is already this address");
        developmentWallet = newDevelopmentWallet;
    }

    function updateMarketingWallet(address newMarketingWallet) external onlyOwner {
        require(marketingWallet != newMarketingWallet, "Lattice: Treasury Wallet is already this address");
        marketingWallet = newMarketingWallet;
    }

    /// @param newBuyFee value magnified by 10
    function updateBuyFee(uint256 newBuyFee) external onlyOwner {
        buyFee = newBuyFee;
    }

    /// @param newSellFee values magnified by 10
    function updateSellFee(uint256[2] calldata newSellFee) external onlyOwner {
        sellFee = newSellFee;
    }

    function updateBuyLockTime(uint256 newBuyLockTime) external onlyOwner {
        require(buyLockTime != newBuyLockTime, "Lattice: Buy Lock Time is already this value");
        buyLockTime = newBuyLockTime;
    }

    function updateSellLockTime(uint256 newSellLockTime) external onlyOwner {
        require(sellLockTime != newSellLockTime, "Lattice: Sell Lock Time is already this value");
        sellLockTime = newSellLockTime;
    }

    function updateLimitTime(uint256 newLimitTime) external onlyOwner {
        require(limitTime != newLimitTime, "Lattice: Limit Time is already this value");
        limitTime = newLimitTime;
    }

    /// @param newBuyLimitPercentage value magnified by 10
    function updateBuyLimitPercentage(uint256 newBuyLimitPercentage) external onlyOwner {
        require(buyLimitPercentage != newBuyLimitPercentage, "Lattice: Buy Limit Percentage is already this value");
        buyLimitPercentage = newBuyLimitPercentage;
    }

    /// @param newSellLimitPercentage value magnified by 10
    function updateSellLimitPercentage(uint256 newSellLimitPercentage) external onlyOwner {
        require(sellLimitPercentage != newSellLimitPercentage, "Lattice: Sell Limit Percentage is already this value");
        sellLimitPercentage = newSellLimitPercentage;
    }

    function updateUniswapV2Router(address newUniswapV2Router) external onlyOwner {
        require(newUniswapV2Router != address(uniswapV2Router), "Lattice: The router is already this address");
        emit UpdateUniswapV2Router(newUniswapV2Router, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newUniswapV2Router);
    }

    function isBlacklisted(address account) external view returns (bool) {
        return _isBlacklisted[account];
    }

    function blackListAddress(address account, bool blacklisted) external onlyOwner {
        require(_isBlacklisted[account] != blacklisted, "Lattice: Account is already the value of 'blacklisted'");
        _isBlacklisted[account] = blacklisted;

        emit BlackListAddress(account, blacklisted);
    }

    function blackListMultipleAddresses(address[] calldata accounts, bool blacklisted) external onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _isBlacklisted[accounts[i]] = blacklisted;
        }

        emit BlackListMultipleAddresses(accounts, blacklisted);
    }

    function isExcludedFromFees(address account) external view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "Lattice: Account is already the value of 'excluded'");
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) external onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    function isExcludedFromLimit(address account) external view returns (bool) {
        return _isExcludedFromLimit[account];
    }

    function excludeFromLimit(address account, bool excluded) public onlyOwner {
        require(_isExcludedFromLimit[account] != excluded, "Lattice: Account is already the value of 'excluded'");
        _isExcludedFromLimit[account] = excluded;

        emit ExcludeFromLimit(account, excluded);
    }

    function excludeMultipleAccountsFromLimit(address[] calldata accounts, bool excluded) external onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromLimit[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromLimit(accounts, excluded);
    }

    function setAutomatedMarketMakerPair(address pair, bool state) public onlyOwner {
        require(automatedMarketMakerPairs[pair] != state, "Lattice: Automated Market Maker Pair is already this state");
        automatedMarketMakerPairs[pair] = state;

        emit SetAutomatedMarketMakerPair(pair, state);
    }

    /* ========== BUY/SELL HELPERS ========== */

    function _isBuy(address from) internal view returns (bool) {
        // Transfer from pair is a buy swap
        return automatedMarketMakerPairs[from];
    }

    function _isSell(address from, address to) internal view returns (bool) {
        // Transfer from non-router address to pair is a sell swap
        return from != address(uniswapV2Router) && automatedMarketMakerPairs[to];
    }

    /* ========== TIME LOCK HANDLER ========== */

    function _handleTimeLock(address from, address to) internal {
        if (_isBuy(from)) {
            if (_isExcludedFromLimit[to]) {
                return;
            }

            if (block.timestamp > getBuyTimeLock[to] + buyLockTime) {
                getBuyTimeLock[to] = block.timestamp;
            }
            else {
                revert("Lattice: Please wait a few minutes for consecutive exchanges");
            }
        }
        else if (_isSell(from, to)) {
            if (_isExcludedFromLimit[from]) {
                return;
            }

            if (block.timestamp > getSellTimeLock[from] + sellLockTime) {
                getSellTimeLock[from] = block.timestamp;
            }
            else {
                revert("Lattice: Please wait a few minutes for consecutive exchanges");
            }
        }
    }

    /* ========== BUYING LIMIT HANLDER ========== */

    function _handleBuyLimit(address to, uint256 amount) internal {
        if (_isExcludedFromLimit[to]) {
            return;
        }

        Limit storage limit = getBuyLimits[to];

        if (limit.account != to) {
            limit.account = to;
            limit.amount = 0;
            limit.startTime = block.timestamp;
        }

        uint256 totalSupply = totalSupply();

        if (limit.amount + amount > totalSupply.mul(buyLimitPercentage).div(1000)) {
            require(block.timestamp > limit.startTime.add(limitTime),
                "Lattice: Daily exchange limit reached. Please try again after limit expires or try a different amount");
        }

        if (block.timestamp > limit.startTime + limitTime) {
            limit.amount = amount;
            limit.startTime = block.timestamp;
        }
        else {
            limit.amount += amount;
        }
    }

    /* ========== SELLING LIMIT HANLDER ========== */

    function _handleSellLimit(address from, uint256 amount) internal {
        if (_isExcludedFromLimit[from]) {
            return;
        }

        Limit storage limit = getSellLimits[from];

        if (limit.account != from) {
            limit.account = from;
            limit.amount = 0;
            limit.startTime = block.timestamp;
        }

        uint256 totalSupply = totalSupply();

        if (limit.amount + amount > totalSupply.mul(sellLimitPercentage).div(1000)) {
            require(block.timestamp > limit.startTime.add(limitTime),
                "Lattice: Daily exchange limit reached. Please try again after limit expires or try a different amount");
        }

        if (block.timestamp > limit.startTime + limitTime) {
            limit.amount = amount;
            limit.startTime = block.timestamp;
        }
        else {
            limit.amount += amount;
        }
    }

    /* ========== INTERNAL TRANSFER LOGIC ========== */

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(!_isBlacklisted[from], "Lattice: tranfer from a blacklisted address");
        require(!_isBlacklisted[to], "Lattice: tranfer to a blacklisted address");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        bool isBuy = _isBuy(from);

        bool isSell = _isSell(from, to);

        if (isBuy || isSell) {
            _handleTimeLock(from, to);
        }

        if (isBuy) {
            if (!_isExcludedFromLimit[to]) {
                _handleBuyLimit(to, amount);
            }

            if (!_isExcludedFromFees[to]) {
                uint256 feeDevelopment = amount.mul(buyFee).div(1000);

                amount -= feeDevelopment;

                super._transfer(from, developmentWallet, feeDevelopment);
            }
        }

        if (isSell) {
            if (!_isExcludedFromLimit[from]) {
                _handleSellLimit(from, amount);
            }

            if (!_isExcludedFromFees[from]) {
                uint256 feeDevelopment = amount.mul(sellFee[0]).div(1000);
                uint256 feeMarketing = amount.mul(sellFee[1]).div(1000);

                amount -= feeDevelopment;
                amount -= feeMarketing;

                super._transfer(from, developmentWallet, feeDevelopment);
                super._transfer(from, marketingWallet, feeMarketing);
            }
        }

        super._transfer(from, to, amount);
    }
}