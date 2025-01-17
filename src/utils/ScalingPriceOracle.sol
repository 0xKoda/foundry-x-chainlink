// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {Timed} from "./../utils/Timed.sol";
import {CoreRef} from "./../refs/CoreRef.sol";
import {Decimal} from "../external/Decimal.sol";
import {Constants} from "./../Constants.sol";
import {Deviation} from "./../utils/Deviation.sol";
import {IScalingPriceOracle} from "./IScalingPriceOracle.sol";
import {BokkyPooBahsDateTimeContract} from "./../external/calendar/BokkyPooBahsDateTimeContract.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ChainlinkClient, Chainlink} from "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "./PriceFeed.sol";
import "./FancyMath.sol";

/// @notice contract that receives a chainlink price feed and then linearly interpolates that rate over
/// a 28 day period into the AER price. Interest is compounded monthly when the rate is updated
contract ScalingPriceOracle is
    Timed,
    ChainlinkClient,
    IScalingPriceOracle,
    BokkyPooBahsDateTimeContract
{
    using SafeCast for *;
    using Deviation for *;
    using Decimal for Decimal.D256;
    using Chainlink for Chainlink.Request;

    /// ---------- Mutable Price Variables ----------
    StandardDev stD;
    event globalVolatility(uint256, uint256);

    /// @notice current amount that oracle price is inflating/deflating by monthly in basis points
    int256 public override monthlyChangeRateBasisPoints;

    /// @notice oracle price. starts off at 1e18 and compounds monthly
    uint256 public override oraclePrice = 1e18;
    enum Currency {
        GBP,
        USD,
        EUR,
        AUD,
        SGD,
        GLOBAL
    }
    struct Sample {
        uint256 timestamp;
        uint256 price;
    }
    struct Basket {
        mapping(Currency => uint256[4]) prices;
        mapping(Currency => uint256[4]) volatility;
        mapping(Currency => uint256[4]) _variance;
        mapping(Currency => uint256[4]) stdev;
        mapping(Currency => uint256[4]) rate;
        uint256 meanVol;
    }
    struct Data {
        uint256 aud;
        uint256 sgd;
        uint256 eur;
        uint256 usd;
        uint256 gbp;
    }
        mapping(Currency => uint256) prices;
        uint256[4] prices;
        mapping(uint256 => _prices) priceByRound;
        mapping(uint256 => uint256) volatilityByRound;

        uint256 price;
        uint256 volatility;
        uint256 _variance;
        uint256 stdev;
        uint256 rate;
    }
    struct Quarter {
        uint256 vol;
        uint256 rr;
    }
    struct data {
    mapping(uint256 =>mapping(Currency => uint256)) vol; // data[round][currency]
    mapping(uint256 => Data) _prices; // data[round] history of price and total round price
    mapping(uint256 => Quarter) quarter; // data[round] history of price and total round price
    }
    enum Status {
        live,
        paused,
        
    }
    Status status;
    mapping(status => data) _Orcale;
    
    /// ---------- Mutable Price Variables ----------

    mapping(uint256 =>mapping(Currency => uint256)) vol; // data[round][currency]
    mapping(uint256 => Data) _prices; // data[round] history of price and total round price
    mapping(uint256 => Quarter) quarter; // data[round] history of price and total round price

    struct Prices {
        uint256 AUD;
        uint256 EUR;
        uint256 GBP;
        uint256 SGD;
        uint256 USD;
    }
    mapping(Currency => uint256) variance;
    mapping(uint256 => Prices) samples;
    mapping(Currency => uint256[4]) _pSample;
    uint256[4] roundIds;
    uint256[4] _prices;
    uint256[4] vol;
    uint256[4] rate;
    uint256[4] V;
    uint256 public globalVolatility;
    uint256 public threshold; // 1% volatility threshold
    uint256 public _quarterTime;

    PriceConsumerV3AUD pAUD;
    PriceConsumerV3GBP pGBP;
    PriceConsumerV3EUR pEUR;
    PriceConsumerV3AUD pSGD;
    PriceConsumerV3AUD pUSD;
    uint256 public _roundId;
    uint256 public _window;

    /// ---------- Mutable CPI Variables Packed Into Single Storage Slot to Save an SSTORE & SLOAD ----------

    /// @notice the current month's CPI data
    uint128 public currentMonth;

    /// @notice the previous month's CPI data
    uint128 public previousMonth;

    /// ---------- Immutable Variables ----------

    /// @notice the time frame over which all changes in CPI data are applied
    /// 28 days was chosen as that is the shortest length of a month
    uint256 public constant override TIMEFRAME = 28 days;

    /// @notice the maximum allowable deviation in basis points for a new chainlink oracle update
    /// only allow price changes by 20% in a month.
    /// Any change over this threshold in either direction will be rejected
    uint256 public constant override MAXORACLEDEVIATION = 2_000;

    /// @notice address of chainlink oracle to send request
    address public immutable oracle;

    /// @notice job id that retrieves the latest CPI data
    bytes32 public immutable jobId;

    /// @notice amount in LINK paid to node operator for each request
    uint256 public immutable fee;

    /// @param _oracle address of chainlink data provider
    /// @param _jobid job id
    /// @param _fee maximum fee paid to chainlink data provider
    /// @param _currentMonth current month's inflation data
    /// @param _previousMonth previous month's inflation data
    constructor(
        address _oracle,
        bytes32 _jobid,
        uint256 _fee,
        uint128 _currentMonth,
        uint128 _previousMonth
    ) Timed(TIMEFRAME) {
        uint256 chainId;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            chainId := chainid()
        }

        if (chainId == 1 || chainId == 42) {
            setPublicChainlinkToken();
        }

        oracle = _oracle;
        jobId = _jobid;
        fee = _fee;

        currentMonth = _currentMonth;
        previousMonth = _previousMonth;

        _initTimed();

        /// calculate new monthly CPI-U rate in basis points based on current and previous month
        int256 aprBasisPoints = getMonthlyAPR();

        /// store data and apply the change rate over the next month to the VOLT price
        _oracleUpdateChangeRate(aprBasisPoints);
    }
    //

    function poke() public {
        require(window < block.timestamp, "Window has not started yet");
        if(window < block.timestamp && _quarterTime < block.timestamp){
            uint256 round = getPrices();
            uint256 _rate = getGlobalVolatility(round);
            oracleUpdateData();
            emit globalVolatility(round, _rate);
            _quarterTime = block.timestamp + TIMEFRAME;
        } else if(window < block.timestamp && _quarterTime > block.timestamp){
            uint256 round = getPrices();
            emit Round(round);
        }
    }

    // ----------- Getters -----------

    function getPrices() public view returns (uint256) {
    uint256 roundID = _roundId + 1;
    uint256 _aud = uint256(pAUD.getLatestPrice());
    uint256 _eur = uint256(pEUR.getLatestPrice());
    uint256 _gbp = uint256(pGBP.getLatestPrice());
    uint256 _sgd = uint256(pSGD.getLatestPrice());
    uint256 _usd = uint256(pUSD.getLatestPrice());
    _prices[roundID].aud = _aud;
    _prices[roundID].eur = _eur;
    _prices[roundID].gbp = _gbp;
    _prices[roundID].sgd = _sgd;
    _prices[roundID].usd = _usd;
    _roundId = roundID;
    _roundVol(Currency.AUD);
    _roundVol(Currency.EUR);
    _roundVol(Currency.GBP);
    _roundVol(Currency.SGD);
    _roundVol(Currency.USD);
    return roundID;
}

    // read-only view returns gVol
    function globalVolatility(uint256 _rId) public view returns (uint256) {
        uint256[4] memory _vol;
        uint256 _audVol  = data[Currency.AUD].volatilityByRound[_rId];
        uint256 _eurVol  = data[Currency.EUR].volatilityByRound[_rId];
        uint256 _gbpVol  = data[Currency.GBP].volatilityByRound[_rId];
        uint256 _sgdVol  = data[Currency.SGD].volatilityByRound[_rId];
        uint256 _usdVol  = data[Currency.USD].volatilityByRound[_rId];  
        _vol[0] = _audVol;
        _vol[1] = _eurVol;
        _vol[2] = _gbpVol;
        _vol[3] = _sgdVol;
        _vol[4] = _usdVol;
        uint256 _gVol = stD.getStandardDeviation(_vol);
        quarter[roundId].volatility = _gVol;
        return _gVol;
    }
    /// Calc Global Volatility, if over threshold, update redemption rate

    function oracleUpdateData() public returns(uint256){
        require(_window > block.timestamp, "Oracle update is not available yet");
        globalVolatility = globalVolatility(_roundId());
        globalVolatility > threshold ? _oracleUpdateChangeRate(0) : _oracleUpdateChangeRate(0);
        return globalVolatility;
    }
    function _roundVol(Currency _currency) public returns (uint256) {
        uint256[4] memory _p;
        uint256 round = roundID;
        for(uint256 i = 0; i < 4; i++){
            _p[i] = _prices[round - i].aud;
        }
        uint256 _Vol = stD.getStandardDeviation(_p);
        _vol[round][_currency] = _Vol;
        return _Vol;
    }




    function _getVolPerCurrencyPerRound(uint256 _rId, Currency _currency) public view returns (uint256) {
        uint256 _uVol = 0;
        uint256 _pR = rId - 1;
        uint256[4] memory _data = data[_rId][_currency].prices;
        uint256 _v = stD.getStandardDeviation(_data);
        volatilityByRound[_rId] = _v; // might be all thats needed.
        




        uint256 _audSum = samples[_rId].AUD + samples[_rId - 1].AUD + samples[_rId - 2].AUD + samples[_rId - 3].AUD;
        uint256 _audMeanP = _audSum / 4;
        uint256 _audvar = ((samples[_rId].AUD - _audMeanP)**int(2)/int(4));
        uint256 _audVol = _audvar.sqrt();
        variance[AUD].push = _audvar;
        uint256 _uVar = (_audvar - (variance[AUD]._pR)) / 4;
        uin256 _vol = (_audVar - _uVar)**int(2)/int(4); 
        uint256 _aS = stD.getStandardDeviation(data[Currency.AUD].prices);
        volaitility[AUD] = _aS;
        


        uint256 _eurSum = samples[_rId].EUR + samples[_rId - 1].EUR + samples[_rId - 2].EUR + samples[_rId - 3].EUR;
        uint256 sum = 
        for (uint256 i = 0; i < 4; i++) {
            _uVol += samples[roundID].AUD[i];
        }
        return _uVol;
    }
    /// @notice get the global volatility of current round
    function getGVol(_rId) public view returns (uint256) {
        uint256[4] memory _gVol;
        _gVol[0] = _vol[rId][Currency.AUD];
        _gVol[1] = _vol[rId][Currency.EUR];
        _gVol[2] = _vol[rId][Currency.GBP];
        _gVol[3] = _vol[rId][Currency.SGD];
        _gVol[4] = _vol[rId][Currency.USD];
        uint256 _gVol = stD.getStandardDeviation(_gVol);
        data[Currency.GLOBAL].vol[_rId].push(globalVol);
        emit globalVolatility(_rId, globalVol);
        return globalVol;
    }

    function getRoundId() public view returns (uint256) {
        uint256 _r = roundIds[0] + 1;
        return roundIds[0];
    }

    /// @notice get the current scaled oracle price
    /// applies the change smoothly over a 28 day period
    /// scaled by 18 decimals
    // prettier-ignore
    function getCurrentOraclePrice() public view override returns (uint256) {
        int256 oraclePriceInt = oraclePrice.toInt256();

        int256 timeDelta = Math.min(block.timestamp - startTime, TIMEFRAME).toInt256();
        int256 pricePercentageChange = oraclePriceInt * monthlyChangeRateBasisPoints / Constants.BP_INT;
        int256 priceDelta = pricePercentageChange * timeDelta / TIMEFRAME.toInt256();

        return (oraclePriceInt + priceDelta).toUint256();
    }

    /// @notice get APR from chainlink data by measuring (current month - previous month) / previous month
    /// @return percentageChange percentage change in basis points over past month
    function getMonthlyAPR() public view returns (int256 percentageChange) {
        int256 delta = int128(currentMonth) - int128(previousMonth);
        percentageChange = (delta * Constants.BP_INT) / int128(previousMonth);
    }

    /// ------------- Public API To Request Chainlink Data -------------

    /// @notice Create a Chainlink request to retrieve API response, find the target
    /// data, then multiply by 1000 (to remove decimal places from data).
    /// @return requestId for this request
    /// only allows 1 request per month after the 14th day
    /// callable by anyone after time period and 14th day of the month
    function requestCPIData()
        external
        afterTimeInit
        returns (bytes32 requestId)
    {
        require(
            getDay(block.timestamp) > 14,
            "ScalingPriceOracle: cannot request data before the 15th"
        );

        Chainlink.Request memory request = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfill.selector
        );

        return sendChainlinkRequestTo(oracle, request, fee);
    }

    /// ------------- Chainlink Node Operator API -------------

    /// @notice Receive the response in the form of
    /// @param _requestId of the chainlink request
    /// @param _cpiData latest CPI data from BLS
    /// called by the chainlink oracle
    function fulfill(bytes32 _requestId, uint256 _cpiData)
        external
        recordChainlinkFulfillment(_requestId)
    {
        _updateCPIData(_cpiData);
    }

    // ----------- Internal state changing api -----------

    /// @notice helper function to store and validate new chainlink data
    /// @param _price latest CPI data from BLS
    /// update will fail if new values exceed deviation threshold of 20% monthly
    function _updateCPIData(uint256 _price, Currency _currency) internal {
        require(
            MAXORACLEDEVIATION.isWithinDeviationThreshold(
                currentMonth.toInt256(),
                _price.toInt256()
            ),
            "ScalingPriceOracle: Chainlink data outside of deviation threshold"
        );

        /// store CPI data, removes stale data
        _addNewMonth(uint128(_price));

        /// calculate new monthly CPI-U rate in basis points
        // int256 aprBasisPoints = getMonthlyAPR();
        int256 r = getMonthlyAPR();
        Currency._currency.prices[0] = _price; // add these as _functions
        Currency._currency.vol[0] = r;
        Currency._currency.variance[0] = r;
        Currency._currency.V[0] =
            ((r - Currency._currency.variance[4]) / r) *
            50000;

        /// pass data to VOLT Price Oracle
        // _oracleUpdateChangeRate(r);
    }

    /// @notice function for chainlink oracle to be able to call in and change the rate
    /// @param newChangeRateBasisPoints the new monthly interest rate applied to the chainlink oracle price
    ///
    /// function effects:
    ///   compounds interest accumulated over period
    ///   set new change rate in basis points for next period
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

        
         = newChangeRateBasisPoints;
    }

    /// @notice this is the only method needed as we will be storing the most recent 2 months of data
    /// @param newMonth the new month to store
    function _addNewMonth(uint128 newMonth) internal {
        previousMonth = currentMonth;

        currentMonth = newMonth;
    }

    function _calculateMonthlyChangeRate() internal {
        int256 r = getMonthlyAPR();
        Currency._currency.prices[0] = currentMonth; // add these as _functions
        Currency._currency.vol[0] = r;
        Currency._currency.variance[0] = r;
        Currency._currency.V[0] =
            ((r - Currency._currency.variance[4]) / r) *
            50000;
    }

    /// @notice helper function to find mean volatility of the basket
    function _getGlobalVolatility() internal returns (uint256) {
        uint256 r = 0;
        for (uint256 i = 0; i < 5; i++) {
            r += Currency._currency.vol[i];
        }
        return r / 5;
    }
}
