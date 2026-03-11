// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MockXcmOracle.sol";

contract MockXcmOracleTest is Test {
    MockXcmOracle public oracle;
    address public owner;
    address public randomUser;

    function setUp() public {
        owner = address(this);
        randomUser = makeAddr("randomUser");
        oracle = new MockXcmOracle();
    }

    // ─── Default Parachain Registration ──────────────────────────────

    function test_defaultParachains_acala() public view {
        uint32 paraId = oracle.getParachainId("acala");
        assertEq(paraId, 2000);
        assertTrue(oracle.isParachainSupported(2000));
    }

    function test_defaultParachains_interlay() public view {
        uint32 paraId = oracle.getParachainId("interlay");
        assertEq(paraId, 2032);
        assertTrue(oracle.isParachainSupported(2032));
    }

    function test_defaultParachains_bifrost() public view {
        uint32 paraId = oracle.getParachainId("bifrost");
        assertEq(paraId, 2030);
        assertTrue(oracle.isParachainSupported(2030));
    }

    function test_defaultParachains_moonbeam() public view {
        uint32 paraId = oracle.getParachainId("moonbeam");
        assertEq(paraId, 2004);
        assertTrue(oracle.isParachainSupported(2004));
    }

    function test_unknownChain_returnsZero() public view {
        assertEq(oracle.getParachainId("unknown"), 0);
    }

    function test_unsupportedParachain() public view {
        assertFalse(oracle.isParachainSupported(9999));
    }

    // ─── Asset State Queries ─────────────────────────────────────────

    function test_queryAssetState_aDOT() public view {
        IXcmOracle.AssetState memory state = oracle.queryAssetState(2000, "aDOT");
        assertTrue(state.exists);
        assertEq(state.totalSupply, 50_000 ether);
        assertEq(state.minterAddress, address(0xACA1));
        assertGt(state.timestamp, 0);
        assertTrue(state.stateHash != bytes32(0));
    }

    function test_queryAssetState_iBTC() public view {
        IXcmOracle.AssetState memory state = oracle.queryAssetState(2032, "iBTC");
        assertTrue(state.exists);
        assertEq(state.totalSupply, 21_000 ether);
    }

    function test_queryAssetState_nonexistent() public view {
        IXcmOracle.AssetState memory state = oracle.queryAssetState(2000, "FAKE");
        assertFalse(state.exists);
        assertEq(state.totalSupply, 0);
    }

    function test_queryAssetState_unregisteredParachain_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(MockXcmOracle.ParachainNotRegistered.selector, 9999));
        oracle.queryAssetState(9999, "aDOT");
    }

    // ─── Admin: Register Parachain ───────────────────────────────────

    function test_registerParachain_byOwner() public {
        oracle.registerParachain("hydration", 2034);
        assertTrue(oracle.isParachainSupported(2034));
        assertEq(oracle.getParachainId("hydration"), 2034);
    }

    function test_registerParachain_byNonOwner_reverts() public {
        vm.prank(randomUser);
        vm.expectRevert(MockXcmOracle.Unauthorized.selector);
        oracle.registerParachain("hydration", 2034);
    }

    // ─── Admin: Set Asset State ──────────────────────────────────────

    function test_setAssetState_byOwner() public {
        bytes32 hash = keccak256("newHash");
        address minter = makeAddr("minter");
        oracle.setAssetState(2000, "newAsset", 1000 ether, minter, hash);

        IXcmOracle.AssetState memory state = oracle.queryAssetState(2000, "newAsset");
        assertTrue(state.exists);
        assertEq(state.totalSupply, 1000 ether);
        assertEq(state.minterAddress, minter);
        assertEq(state.stateHash, hash);
    }

    function test_setAssetState_unregisteredParachain_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(MockXcmOracle.ParachainNotRegistered.selector, 9999));
        oracle.setAssetState(9999, "asset", 1000, address(0), bytes32(0));
    }

    // ─── Anomaly Injection ───────────────────────────────────────────

    function test_injectAnomaly_changesSupply() public {
        IXcmOracle.AssetState memory before_ = oracle.queryAssetState(2000, "aDOT");
        bytes32 hashBefore = before_.stateHash;

        // Inject 10x supply spike
        oracle.injectAnomaly(2000, "aDOT", 500_000 ether);

        IXcmOracle.AssetState memory after_ = oracle.queryAssetState(2000, "aDOT");
        assertEq(after_.totalSupply, 500_000 ether);
        // Hash should NOT be updated (intentional mismatch)
        assertEq(after_.stateHash, hashBefore);
    }

    function test_injectAnomaly_byNonOwner_reverts() public {
        vm.prank(randomUser);
        vm.expectRevert(MockXcmOracle.Unauthorized.selector);
        oracle.injectAnomaly(2000, "aDOT", 500_000 ether);
    }
}
