pragma solidity ^0.8.7;
import "../lib/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import "./PriceFeed.sol";
import "./FancyMath.sol";

// import "./ScalingPriceOracle.sol";
interface Handler {
    function getMinPrice(address _fx) external view returns (uint256);
}

contract volOracle {
    StandardDev stD;
    uint256 public lastTimeStamp;
    uint256 public lastPrice;
    uint256 public quarterTime;
    uint256 public globalVolatility;
    uint256 public threshold; // 1% volatility threshold
    uint256 public _quarterTime;
    uint256 public override oraclePrice = 1e18;
    uint256 public WINDOW = 30 days;
    uint256 public roundId;
    int256 public override monthlyChangeRateBasisPoints;
    uint256 public TIMEFRAME = 90 days;
    uint256 public override DEVIATOR = 1000000000;
    Handler handler;

    PriceConsumerV3AUD pAUD;
    PriceConsumerV3GBP pGBP;
    PriceConsumerV3EUR pEUR;
    PriceConsumerV3AUD pSGD;
    PriceConsumerV3AUD pUSD;
    enum Currency {
        GBP,
        USD,
        EUR,
        AUD,
        SGD,
        GLOBAL
    }

    struct Data {
        uint256 aud;
        uint256 sgd;
        uint256 eur;
        uint256 usd;
        uint256 gbp;
    }
    struct Quarter {
        uint256 vol;
        uint256 rr;
    }
    mapping(Currency => Data) public data;
    mapping(uint256 => mapping(Currency => uint256)) vol;
    mapping(uint256 => mapping(Currency => uint256)) prices; // data[round][currency]
    mapping(uint256 => Data) _prices; // data[round] history of price and total round price
    mapping(uint256 => Quarter) quarter; // data[round] history of price and total round price

    constructor(uint256 updateInterval) {
        WINDOW = updateInterval;
        lastTimeStamp = block.timestamp;
        lastPrice = 0;
        handler = 0x1785e8491e7e9d771b2A6E9E389c25265F06326A;
    }

    function poke() public {
        require(WINDOW < block.timestamp, "Window has not started yet");
        if (WINDOW < block.timestamp && quarterTime < block.timestamp) {
            uint256 round = getPrices();
            uint256 _rate = _getGlobalVolatility(round);
            oracleUpdateData();
            emit globalVolatility(round, _rate);
            quarterTime = block.timestamp + TIMEFRAME;
        } else if (WINDOW < block.timestamp && quarterTime > block.timestamp) {
            uint256 round = getPrices();
            emit Round(round);
        }
    }

    function getPrices() public view returns (uint256) {
        uint256 _roundId = roundId + 1;
        uint256 _aud = uint256(
            handler.getMinPrice(0x7E141940932E3D13bfa54B224cb4a16510519308)
        );
        uint256 _eur = uint256(pEUR.getLatestPrice());
        uint256 _gbp = uint256(pGBP.getLatestPrice());
        uint256 _sgd = uint256(pSGD.getLatestPrice());
        uint256 _usd = uint256(pUSD.getLatestPrice());
        prices[_roundId][Currency.AUD] = _aud;
        prices[_roundId][Currency.EUR] = _eur;
        prices[_roundId][Currency.GBP] = _gbp;
        prices[_roundId][Currency.SGD] = _sgd;
        prices[_roundId][Currency.USD] = _usd;
        _roundId = roundId;
        _roundVol(Currency.AUD);
        _roundVol(Currency.EUR);
        _roundVol(Currency.GBP);
        _roundVol(Currency.SGD);
        _roundVol(Currency.USD);
        return roundId;
    }

    function global_Volatility(uint256 _rId) public view returns (uint256) {
        uint256[4] memory _vol;
        uint256 _audVol = data[Currency.AUD].volatilityByRound[_rId];
        uint256 _eurVol = data[Currency.EUR].volatilityByRound[_rId];
        uint256 _gbpVol = data[Currency.GBP].volatilityByRound[_rId];
        uint256 _sgdVol = data[Currency.SGD].volatilityByRound[_rId];
        uint256 _usdVol = data[Currency.USD].volatilityByRound[_rId];
        _vol[0] = _audVol;
        _vol[1] = _eurVol;
        _vol[2] = _gbpVol;
        _vol[3] = _sgdVol;
        _vol[4] = _usdVol;
        uint256 _gVol = stD.getStandardDeviation(_vol);
        quarter[roundId].volatility = _gVol;
        return _gVol;
    }

    function oracleUpdateData() public returns (uint256) {
        require(WINDOW > block.timestamp, "Oracle update is not available yet");
        globalVolatility = globalVolatility(roundId);
        globalVolatility > threshold
            ? _oracleUpdateChangeRate(change())
            : _oracleUpdateChangeRate(0);
        return globalVolatility;
    }

    function change() internal returns (int256) {
        int256 newChangeRateBasisPoints;
        uint256 r = (globalVolatility - quarter[roundId].volatility) /
            quarter[roundId - 1].volatility;
        if (globalVolatility > threshold && quarter < block.timestamp) {
            if (r < DEVIATOR) {
                newChangeRateBasisPoints = int256(r);
                return newChangeRateBasisPoints;
            } else {
                return 0;
            }
        }
        return;
    }

    function _roundVol(Currency _currency) public returns (uint256) {
        uint256[4] memory _p;
        uint256 round = roundId;
        _p.push(prices[round][_currency]);
        _p.push(prices[round - 1][_currency]);
        _p.push(prices[round - 2][_currency]);
        _p.push(prices[round - 3][_currency]);
        uint256 _Vol = stD.getStandardDeviation(_p);
        vol[round][_currency] = _Vol;
        return _Vol;
    }

    function _oracleUpdateChangeRate(int256 newChangeRateBasisPoints) internal {
        /// compound the interest with the current rate
        oraclePrice = getCurrentOraclePrice();

        int256 currentChangeRateBasisPoints = monthlyChangeRateBasisPoints; /// save 1 SSLOAD

        /// emit even if there isn't an update
        emit CPIMonthlyChangeRateUpdate(
            currentChangeRateBasisPoints,
            newChangeRateBasisPoints
        );

        /// if the oracle change rate is the same as last time, save an SSTORE
        if (newChangeRateBasisPoints == currentChangeRateBasisPoints) {
            return;
        }

        monthlyChangeRateBasisPoints = newChangeRateBasisPoints;
    }

    function getCurrentOraclePrice() public view override returns (uint256) {
        int256 oraclePriceInt = oraclePrice.toInt256();

        int256 timeDelta = Math
            .min(block.timestamp - startTime, WINDOW)
            .toInt256();
        int256 pricePercentageChange = (oraclePriceInt *
            monthlyChangeRateBasisPoints) / Constants.BP_INT;
        int256 priceDelta = (pricePercentageChange * timeDelta) /
            WINDOW.toInt256();

        return (oraclePriceInt + priceDelta).toUint256();
    }

    function _getGlobalVolatility() internal returns (uint256) {
        uint256 r = 0;
        for (uint256 i = 0; i < 5; i++) {
            r += Currency._currency.vol[i];
        }
        return r / 5;
    }
}
