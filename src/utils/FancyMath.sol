// SPDX-License-Identifier: GNU GPL v3

pragma solidity ^0.8.7;
import "../lib/openzeppelin-contracts/contracts/utils/math/SafeMath.sol";

library StandardDev {
    // you might test it - e.g. with  [2, 20, 50]

    function getBollingerBands(int256[] memory sequence, uint256 spreadFactor)
        public
        pure
        returns (
            int256[] memory,
            int256[] memory,
            int256[] memory
        )
    {
        require(spreadFactor > 0);

        uint256 i = 0;

        int256[] memory smaBand = getSMABand(sequence);
        int256[] memory lowerBand = new int256[](sequence.length);
        int256[] memory upperBand = new int256[](sequence.length);

        for (i; i < smaBand.length; i++) {
            int256 standardDeviation = getStandardDeviation(
                getArrayUntil(smaBand, i + 1)
            );

            require(standardDeviation > 0);

            lowerBand[i] =
                smaBand[i] -
                (standardDeviation * int256(spreadFactor));
            upperBand[i] =
                smaBand[i] +
                (standardDeviation * int256(spreadFactor));

            // log("standardDeviation", standardDeviation);
        }

        return (smaBand, lowerBand, upperBand);
    }

    function getAverage(int256[] memory sequence) public pure returns (int256) {
        int256 sum = 0;
        uint256 i = 0;
        for (i; i < sequence.length; i++) {
            sum = sum + sequence[i];
        }

        return sum / int256(sequence.length);
    }

    function getArrayUntil(int256[] memory array, uint256 offset)
        public
        pure
        returns (int256[] memory)
    {
        uint256 counter = 0;
        int256[] memory result = new int256[](offset);
        for (counter; counter < offset; counter++) {
            result[counter] = array[counter];
        }

        return result;
    }

    function getSMABand(int256[] memory sequence)
        public
        pure
        returns (int256[] memory)
    {
        require(sequence.length > 0);

        int256[] memory result = new int256[](3);

        uint256 i = 0;

        for (i; i < sequence.length; i++) {
            result[i] = getAverage(getArrayUntil(sequence, i + 1));
        }

        return result;
    }

    function getStandardDeviation(int256[] memory sequence)
        public
        pure
        returns (int256)
    {
        int256 average = getAverage(sequence);

        int256[]
            memory substractedMeanFromEachAndSquared = substractAverageFromEachAndSquare(
                sequence,
                average
            );

        int256 averageOfSquaredDifferences = getAverage(
            substractedMeanFromEachAndSquared
        );

        return sqrt(averageOfSquaredDifferences);
    }

    function substractAverageFromEachAndSquare(
        int256[] memory sequence,
        int256 average
    ) public pure returns (int256[] memory) {
        int256[] memory squaredDifferences = new int256[](sequence.length);

        uint256 i = 0;

        for (i; i < sequence.length; i++) {
            squaredDifferences[i] = substractAverageAndSquare(
                sequence[i],
                average
            );
        }

        return squaredDifferences;
    }

    // could be replaced as soon as https://github.com/OpenZeppelin/openzeppelin-contracts/pull/3282 is merged...
    function sqrt(int256 x) public pure returns (int256 y) {
        int256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function substractAverageAndSquare(int256 entry, int256 average)
        public
        pure
        returns (int256)
    {
        return (entry - average)**2;
    }
}
