/**
 * Coin Bingo!
 * 
 * This contract is meant to be more of a joke than anything else, I wrote it
 * whilst a little bored. Please thoroughly read this if you intend on actually
 * using it, I haven't put any money through it and so I won't attest at all to
 * how (un)safe it is.
 * 
 * I haven't written any tests, I haven't put out a bug bounty, I haven't even
 * emailed Vitalik for a security audit and I don't intend on doing any of those
 * things.
 * 
 * Have fun.
 */

pragma solidity ^0.4.11;
import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";

contract CoinBingo is usingOraclize {
    
    int8 constant INVALID_IDENTIFIER = -127;
    uint256 constant BUY_IN = 0.1 ether;
    uint256 constant DAY_IN_SECONDS = 86400;
    
    string[] public coins;
    int256[] public coinGains;
    uint8 public totalBets;
    uint8 public winnerCount;
    uint8 public winningCoin;
    uint8 public currentRound;
    uint8 public maxParticipants;
    uint8 public currentCoinIndex = 0;
    uint256 public betsAllowedUntil;
    bool public draw;
    bool public dormant = true;
    bool public bingoCalled;
    mapping(address => uint8) public bets;
    mapping(uint32 => uint8) public betCount;
    mapping(bytes32 => uint8) public queries;
    
    event LogCoinGains(string _coin, int256 _gains);
    event LogWinningCoin(string _coin, int256 _gains);
    event LogWithdrawal(address _winner, uint256 _amount);
    event LogRoundStarted(uint8 _currentRound, uint8 _maxParticipants);
    event LogNewParticipant(address _participant, string _coin, uint _bets, uint256 _pot);

    modifier whileBetsAllowed() {
        if (block.timestamp > betsAllowedUntil) throw;
        _;
    }

    modifier afterPriceAction() {
        if ((block.timestamp - (7 * DAY_IN_SECONDS)) < betsAllowedUntil) throw;
        _;
    }

    modifier whileDormant() {
        if (!dormant) throw;
        _;
    }
    
    modifier withdrawalsAllowed() {
        if (!dormant && block.timestamp > betsAllowedUntil) throw;
        _;
    }
    
    function CoinBingo() {
        
    }

    function start(uint8 _maxParticipants) whileDormant external {
        currentRound++;
        betsAllowedUntil = block.timestamp + (2 * DAY_IN_SECONDS);
        maxParticipants = _maxParticipants;
        totalBets = 0;
        winnerCount = 0;
        dormant = false;
        bingoCalled = false;
        currentCoinIndex = 0;
        LogRoundStarted(currentRound, _maxParticipants);
    }
    
    function addCoin(string _coin) whileBetsAllowed external {
        coins.push(_coin);
    }
    
    function getCoin(uint _index) external constant returns (string) {
        return coins[_index];
    }
    
    // join the game with the coin of your choice, and 0.1 eth
    function join(uint8 _coin) payable whileBetsAllowed external {
        if (msg.value != BUY_IN) throw;
        if (_coin < 0 || _coin > coins.length || coins.length > 254) throw;
        if (++totalBets > maxParticipants) throw;
        bets[msg.sender] = _coin;
        betCount[_coin]++;
        LogNewParticipant(msg.sender, coins[_coin], totalBets, this.balance);
    }

    // once the week is up, anyone can call this (it's in the interest of any winner
    // to do so!) and the funds will be distributed
    function bingo() payable afterPriceAction external {
        if (bingoCalled) throw;
        bingoCalled = true;
        getCoinGains(currentCoinIndex);
    }
    
    // coming out of my cave and i've been doing just fine but i gotta be up cmon oraclize
    function getCoinGains(uint8 _coin) internal {
        string memory url = strConcat(
            "json(https://api.coinmarketcap.com/v1/ticker/",
            coins[_coin],
            "/?convert=USD).0.percent_change_7d"
        );
        queries[oraclize_query(block.timestamp, "URL", url)] = _coin;
    }

    // oraclize brings home the dough and then we finalise the bingo card
    function __callback(bytes32 myid, string result, bytes proof) {
        // if (msg.sender != oraclize_cbAddress()) throw;
        coinGains.push(parseIntProperly(result));
        LogCoinGains(coins[queries[myid]], coinGains[queries[myid]]);
        if (++currentCoinIndex < coins.length) {
            getCoinGains(currentCoinIndex);
        } else {
            finaliseBingo();
        }
    }

    // compare all the gains and find out who won
    function finaliseBingo() internal {
        setWinner(0);
        for (uint8 i = 1; i < coinGains.length; i++) {
            if (coinGains[i] > coinGains[winningCoin]) {
                setWinner(i);
            } else if (coinGains[i] == coinGains[winningCoin]) {
                // draw between two or more coins! everyone can have their eth back
                draw = true;
                winnerCount = totalBets;
            }
            betCount[i] = 0;
        }
        dormant = true;
        LogWinningCoin(coins[winningCoin], coinGains[winningCoin]);
    }

    function setWinner(uint8 _coin) internal {
        winningCoin = _coin;
        winnerCount = uint8(betCount[_coin]);
        draw = false;
    }

    // if you bet on the right coin, you can have a share of the pie!
    function withdraw() withdrawalsAllowed external returns (bool) {
        if (bets[msg.sender] == winningCoin) {
            if (msg.sender.send(this.balance / winnerCount)) {
                LogWithdrawal(msg.sender, this.balance / winnerCount);
            }
        } else if (draw || winnerCount == 0) {
            if(msg.sender.send(this.balance / totalBets)) {
                LogWithdrawal(msg.sender, this.balance / totalBets);
            }
        }
    }
    
    // i stole this from oraclize's API, but their version doesn't handle negative
    // numbers, so i changed it a little bit and gave it a smarmy name
    function parseIntProperly(string _a) internal returns (int256) {
        bytes memory bresult = bytes(_a);
        if (bresult.length == 0) return INVALID_IDENTIFIER;
        int mint = 0;
        bool decimals = false;
        bool negative = false;
        for (uint i=0; i<bresult.length; i++){
            if ((bresult[i] >= 48)&&(bresult[i] <= 57)){
                if (decimals) break;
                mint *= 10;
                mint += int(bresult[i]) - 48;
            } else if (bresult[i] == 45) {
                negative = true;
            } else if (bresult[i] == 46) {
                decimals = true;
            }
        }
        return negative ? ~mint : mint;
    }
    
} 
