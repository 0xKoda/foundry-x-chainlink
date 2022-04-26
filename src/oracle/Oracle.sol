pragma solidity ^0.8.0;
import "../utils/FancyMath.sol";
pragma experimental ABIEncoderV2;

interface IStdReference {
    StandardDev std;
    /// A structure returned whenever someone requests for standard reference data.
    struct ReferenceData {
        uint256 rate; // base/quote exchange rate, multiplied by 1e18.
        uint256 lastUpdatedBase; // UNIX epoch of the last time when base price gets updated.
        uint256 lastUpdatedQuote; // UNIX epoch of the last time when quote price gets updated.
    }

    /// Returns the price data for the given base/quote pair. Revert if not available.
    function getReferenceData(string memory _base, string memory _quote)
        external
        view
        returns (ReferenceData memory);

    /// Similar to getReferenceData, but with multiple base/quote pairs at once.
    function getReferenceDataBulk(string[] memory _bases, string[] memory _quotes)
        external
        view
        returns (ReferenceData[] memory);
}

contract Oracle {
    IStdReference ref;
    enum Currency {
        EUR,
        AUD,
        USD,
        GBP,
        GLOBAL
    }
    struct Prices {
        Currency base;
        uint256 price;
        uint256 lastPrice;
        uint256 timestamp;
        uint256 change; //variances
        uint256 vol; //volatility of last 4 prices
    }
    // must return an object with currency as key and price as value

    mapping (uint256 => Prices[]) public _prices;
    uint256 roundId;

    constructor(IStdReference _ref) public {
        ref = _ref;
    }

    function getPrice() external view returns (uint256){
        IStdReference.ReferenceData memory data = ref.getReferenceData("BTC","USD");
        return data.rate;
    }
     // must return an object with currency as key and price as value
    function getMultiPrices() external view returns (uint256[] memory){
        string[] memory baseSymbols = new string[](3);
        baseSymbols[0] = "AUD";
        baseSymbols[1] = "GBP";
        baseSymbols[2] = "EUR";
        baseSymbols[3] = "USD";


        string[] memory quoteSymbols = new string[](4);
        quoteSymbols[0] = "USD";
        quoteSymbols[1] = "USD";
        quoteSymbols[2] = "USD";
        quoteSymbols[3] = "EUR";
        IStdReference.ReferenceData[] memory data = ref.getReferenceDataBulk(baseSymbols,quoteSymbols);

        uint256[] memory prices = new uint256[](4);
        prices[0] = data[0].rate;
        prices[1] = data[1].rate;
        prices[2] = data[2].rate;
        prices[3] = data[3].rate;
        return prices;
    }
    function write(uint256[4] prices) public {
        _prices[roundId][0].price = prices[0];
        _prices[roundId][0].base = Currency.AUD;
        _prices[roundId][0].timestamp = block.timestamp;
        _prices[roundId][0].lastPrice = _prices[roundId - 1][0].price;

        _prices[] = _prices[0];
        _prices[1] = _prices[1];
    }
    function vol(Currency _base) public returns(uint256){
        int256[] memory prices = new int256[](3);
        prices[0] = int256(_prices[roundId][0].price);
        prices[1] = int256(_prices[roundId - 1][0].price);
        prices[2] = int256(_prices[roundId - 2][0].price);
        prices[3] = int256(_prices[roundId - 3][0].price);
        int256 vol = std.getStandardDeviation(prices);
        return uint256(vol);
    }

    function savePrice(string memory base, string memory quote) external {
        IStdReference.ReferenceData memory data = ref.getReferenceData(base,quote);
        price = data.rate;
    }
}