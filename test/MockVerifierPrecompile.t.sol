// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MockVerifierPrecompile.sol";

contract MockVerifierPrecompileTest is Test {
    MockVerifierPrecompile public precompile;

    function setUp() public {
        precompile = new MockVerifierPrecompile();
    }

    // ─── Hash Verification ───────────────────────────────────────────

    function test_verifyHash_matching() public view {
        bytes32 hash = keccak256("test");
        assertTrue(precompile.verifyHash(hash, hash));
    }

    function test_verifyHash_different() public view {
        bytes32 a = keccak256("test_a");
        bytes32 b = keccak256("test_b");
        assertFalse(precompile.verifyHash(a, b));
    }

    function test_verifyHash_zero() public view {
        assertTrue(precompile.verifyHash(bytes32(0), bytes32(0)));
    }

    // ─── Anomaly Detection ───────────────────────────────────────────

    function test_detectAnomaly_noChange() public view {
        (bool isAnomaly, uint8 anomalyType,) = precompile.detectAnomaly(1000, 1000, 200);
        assertFalse(isAnomaly);
        assertEq(anomalyType, 0);
    }

    function test_detectAnomaly_smallIncrease() public view {
        // 10% increase, threshold 200% — normal
        (bool isAnomaly,,) = precompile.detectAnomaly(1100, 1000, 200);
        assertFalse(isAnomaly);
    }

    function test_detectAnomaly_supplySpike() public view {
        // 500% increase, threshold 200%
        (bool isAnomaly, uint8 anomalyType, uint8 severity) = precompile.detectAnomaly(6000, 1000, 200);
        assertTrue(isAnomaly);
        assertEq(anomalyType, 1); // SupplySpike
        assertGt(severity, 0);
    }

    function test_detectAnomaly_exactThreshold() public view {
        // 200% increase, threshold 200%
        (bool isAnomaly, uint8 anomalyType,) = precompile.detectAnomaly(3000, 1000, 200);
        assertTrue(isAnomaly);
        assertEq(anomalyType, 1); // SupplySpike
    }

    function test_detectAnomaly_supplyDrop() public view {
        // 80% drop, threshold 50%
        (bool isAnomaly, uint8 anomalyType,) = precompile.detectAnomaly(200, 1000, 50);
        assertTrue(isAnomaly);
        assertEq(anomalyType, 2); // SupplyDrop
    }

    function test_detectAnomaly_zeroPrevious() public view {
        (bool isAnomaly,,) = precompile.detectAnomaly(1000, 0, 200);
        assertFalse(isAnomaly);
    }

    function test_detectAnomaly_bothZero() public view {
        (bool isAnomaly,,) = precompile.detectAnomaly(0, 0, 200);
        assertFalse(isAnomaly);
    }

    // ─── Score Calculation ───────────────────────────────────────────

    function test_calculateScore_allGoodMaxHistory() public view {
        // supply(30) + minter(25) + hash(30) + history(15*10/10=15) = 100
        uint8 score = precompile.calculateScore(true, true, true, 10);
        assertEq(score, 100);
    }

    function test_calculateScore_allGoodNoHistory() public view {
        // supply(30) + minter(25) + hash(30) + history(0) = 85
        uint8 score = precompile.calculateScore(true, true, true, 0);
        assertEq(score, 85);
    }

    function test_calculateScore_supplyFail() public view {
        // supply(0) + minter(25) + hash(30) + history(15) = 70
        uint8 score = precompile.calculateScore(false, true, true, 10);
        assertEq(score, 70);
    }

    function test_calculateScore_allFail() public view {
        uint8 score = precompile.calculateScore(false, false, false, 0);
        assertEq(score, 0);
    }

    function test_calculateScore_partialHistory() public view {
        // supply(30) + minter(25) + hash(30) + history(15*5/10=7) = 92
        uint8 score = precompile.calculateScore(true, true, true, 5);
        assertEq(score, 92);
    }

    function test_calculateScore_historyCappedAt10() public view {
        uint8 score10 = precompile.calculateScore(true, true, true, 10);
        uint8 score100 = precompile.calculateScore(true, true, true, 100);
        assertEq(score10, score100);
    }

    // ─── Score with Anomaly ──────────────────────────────────────────

    function test_scoreWithAnomaly_noAnomaly() public view {
        uint8 score = precompile.calculateScoreWithAnomaly(true, true, true, 10, false, 0);
        assertEq(score, 100);
    }

    function test_scoreWithAnomaly_supplySpikeCap() public view {
        // Base would be 100 but capped at 20
        uint8 score = precompile.calculateScoreWithAnomaly(true, true, true, 10, true, 1);
        assertEq(score, 20);
    }

    function test_scoreWithAnomaly_supplyDropCap() public view {
        // Base would be 100 but capped at 35
        uint8 score = precompile.calculateScoreWithAnomaly(true, true, true, 10, true, 2);
        assertEq(score, 35);
    }
}
