pragma solidity ^0.8.7;
import "../lib/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import "./PriceFeed.sol";
import {StandardDev} from "./FancyMath.sol";

// import "./ScalingPriceOracle.sol";
interface Handler {
    function getMinPrice(address _fx) external view returns (uint256);
}

contract volOracle {
    /// @notice the denominator for basis points granularity (10,000)
    uint256 public constant BASIS_POINTS_GRANULARITY = 10_000;

    /// @notice the denominator for basis points granularity (10,000) expressed as an int data type
    int256 public constant BP_INT = int256(BASIS_POINTS_GRANULARITY);
    uint256 public lastTimeStamp;
    uint256 public lastPrice;
    uint256 public quarterTime;
    int256 public globalVolatility;
    int256 public threshold; // 1% volatility threshold
    uint256 public _quarterTime;
    uint256 public oraclePrice = 1e18;
    uint256 public WINDOW = 30 days;
    uint256 public roundId;
    int256 public monthlyChangeRateBasisPoints;
    uint256 public TIMEFRAME = 90 days;
    int256 public DEVIATOR = 1000000000;
    Handler handler;
    address private pAUD;
    address private pEUR;
    address private pPHP = 0x3d147cD9aC957B2a5F968dE9d1c6B9d0872286a0;
    uint256 public startTime;

    event Round(uint256);
    event RRMonthlyChangeRateUpdate(
        uint256 _monthlyChangeRateBasisPoints,
        uint256 _roundId
    );

    // PriceConsumerV3AUD pAUD;
    // PriceConsumerV3GBP pGBP;
    // PriceConsumerV3EUR pEUR;
    // PriceConsumerV3AUD pSGD;
    // PriceConsumerV3AUD pUSD;

    enum Currency {
        EUR,
        AUD,
        PHP,
        GLOBAL
    }

    struct Data {
        uint256 aud;
        uint256 php;
        uint256 eur;
    }
    struct Quarter {
        int256 vol;
        uint256 rr;
    }
    mapping(Currency => Data) public data;
    mapping(uint256 => mapping(Currency => int256)) vol;
    mapping(uint256 => mapping(Currency => int256)) prices; // data[round][currency]
    mapping(uint256 => Data) _prices; // data[round] history of price and total round price
    mapping(uint256 => Quarter) quarter; // data[round] history of price and total round price

    constructor(uint256 updateInterval) {
        WINDOW = updateInterval;
        lastTimeStamp = block.timestamp;
        lastPrice = 0;
        handler = Handler(0x1785e8491e7e9d771b2A6E9E389c25265F06326A);
        startTime = block.timestamp;
    }

    function poke() public {
        require(WINDOW < block.timestamp, "Window has not started yet");
        if (WINDOW < block.timestamp && quarterTime < block.timestamp) {
            uint256 round = getPrices();
            int256 _rate = global_Volatility(round);
            oracleUpdateData();
            oracleUpdateData();
            quarterTime = block.timestamp + TIMEFRAME;
        } else if (WINDOW < block.timestamp && quarterTime > block.timestamp) {
            uint256 round = getPrices();
            emit Round(round);
        }
    }

    function getPrices() public view returns (uint256) {
        uint256 _roundId = roundId + 1;
        uint256 _aud = handler.getMinPrice(
            0x7E141940932E3D13bfa54B224cb4a16510519308
        );
        uint256 _eur = handler.getMinPrice(
            0x116172B2482c5dC3E6f445C16Ac13367aC3FCd35
        );
        uint256 _php = handler.getMinPrice(
            0x3d147cD9aC957B2a5F968dE9d1c6B9d0872286a0
        );
        prices[_roundId][Currency.AUD] = int256(_aud);
        prices[_roundId][Currency.EUR] = int256(_eur);
        prices[_roundId][Currency.PHP] = int256(_php);
        _roundId = roundId;
        _roundVol(Currency.AUD);
        _roundVol(Currency.EUR);
        _roundVol(Currency.PHP);
        return roundId;
    }

    function global_Volatility(uint256 _rId) public view returns (int256) {
        int256[] memory _vol;
        int256 _audVol = vol[_rId][Currency.AUD];
        int256 _eurVol = vol[_rId][Currency.EUR];
        int256 _phpVol = vol[_rId][Currency.PHP];
        _vol[0] = _audVol;
        _vol[1] = _eurVol;
        _vol[2] = _phpVol;
        int256 _gVol = StandardDev.getStandardDeviation(_vol);
        quarter[roundId].vol = _gVol;
        return _gVol;
    }

    function oracleUpdateData() public returns (int256) {
        require(WINDOW > block.timestamp, "Oracle update is not available yet");
        globalVolatility = global_Volatility(roundId);
        globalVolatility > threshold
            ? _oracleUpdateChangeRate(change())
            : _oracleUpdateChangeRate(0);
        return globalVolatility;
    }

    function change() internal returns (int256) {
        int256 newChangeRateBasisPoints;
        int256 r = (globalVolatility - quarter[roundId].vol) /
            quarter[roundId - 1].vol;
        if (globalVolatility > threshold && TIMEFRAME < block.timestamp) {
            if (r < DEVIATOR) {
                newChangeRateBasisPoints = int256(r);
                return newChangeRateBasisPoints;
            } else {
                return 0;
            }
        }
    }

    function _roundVol(Currency _currency) public returns (int256) {
        int256[] memory _p;
        uint256 round = roundId;
        _p[0] = prices[round][_currency];
        _p[1] = prices[round - 1][_currency];
        _p[2] = prices[round - 2][_currency];
        _p[3] = prices[round - 3][_currency];
        int256 _Vol = StandardDev.getStandardDeviation(_p);
        vol[round][_currency] = _Vol;
        return _Vol;
    }

    function _oracleUpdateChangeRate(int256 newChangeRateBasisPoints) internal {
        /// compound the interest with the current rate
        oraclePrice = getCurrentOraclePrice();

        int256 currentChangeRateBasisPoints = monthlyChangeRateBasisPoints; /// save 1 SSLOAD

        /// emit even if there isn't an update
        emit RRMonthlyChangeRateUpdate(
            uint256(currentChangeRateBasisPoints),
            uint256(newChangeRateBasisPoints)
        );

        /// if the oracle change rate is the same as last time, save an SSTORE
        if (newChangeRateBasisPoints == currentChangeRateBasisPoints) {
            return;
        }

        monthlyChangeRateBasisPoints = newChangeRateBasisPoints;
    }

    function getCurrentOraclePrice() public view returns (uint256) {
        int256 oraclePriceInt = int256(oraclePrice);

        int256 timeDelta = int256(
            Math.min(block.timestamp - startTime, WINDOW)
        );

        int256 pricePercentageChange = (oraclePriceInt *
            monthlyChangeRateBasisPoints) / BP_INT;
        int256 priceDelta = (pricePercentageChange * timeDelta) /
            int256(WINDOW);

        return uint256(oraclePriceInt + priceDelta);
    }
}
// 0x8c064bCf7C0DA3B3b090BAbFE8f3323534D84d68
// uint256 _eur = uint256(pEUR.getLatestPrice());
// uint256 _gbp = uint256(pGBP.getLatestPrice());
// uint256 _sgd = uint256(pSGD.getLatestPrice());
// uint256 _usd = uint256(pUSD.getLatestPrice());
