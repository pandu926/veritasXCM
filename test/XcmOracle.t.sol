// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/XcmOracle.sol";
import "../src/IXcm.sol";

/// @notice Mock of the XCM precompile for testing environments
/// @dev Simulates xcmSend/xcmExecute/weighMessage at unit test level
contract MockXcmPrecompile is IXcm {
    // Record sent messages for assertions
    struct SentMessage {
        bytes destination;
        bytes message;
    }

    SentMessage[] public sentMessages;

    function xcmExecute(bytes calldata, Weight calldata) external override {
        // No-op in mock
    }

    function xcmSend(bytes calldata destination, bytes calldata message) external override {
        sentMessages.push(SentMessage(destination, message));
    }

    function weighMessage(bytes calldata) external pure override returns (Weight memory weight) {
        return Weight(1_000_000, 65_536);
    }

    function getSentCount() external view returns (uint256) {
        return sentMessages.length;
    }
}

contract XcmOracleTest is Test {
    XcmOracle public oracle;
    address public owner;
    address public reporter;
    address public randomUser;

    event XcmQueryDispatched(uint32 indexed paraId, string assetId, bytes xcmMessage);
    event AssetStateReported(uint32 indexed paraId, string assetId, uint256 supply);
    event ParachainRegistered(uint32 indexed paraId, string name);

    function setUp() public {
        owner = address(this);
        reporter = makeAddr("reporter");
        randomUser = makeAddr("randomUser");

        // Deploy mock XCM precompile at the fixed address
        MockXcmPrecompile mockXcm = new MockXcmPrecompile();
        vm.etch(0x00000000000000000000000000000000000a0000, address(mockXcm).code);

        oracle = new XcmOracle();
        oracle.setReporter(reporter, true);
    }

    // ─── Default Parachains ──────────────────────────────────────────

    function test_defaultParachains_registered() public view {
        assertTrue(oracle.isParachainSupported(2000)); // Acala
        assertTrue(oracle.isParachainSupported(2032)); // Interlay
        assertTrue(oracle.isParachainSupported(2030)); // Bifrost
        assertTrue(oracle.isParachainSupported(2004)); // Moonbeam
    }

    function test_chainNameResolution() public view {
        assertEq(oracle.getParachainId("acala"), 2000);
        assertEq(oracle.getParachainId("interlay"), 2032);
        assertEq(oracle.getParachainId("bifrost"), 2030);
        assertEq(oracle.getParachainId("moonbeam"), 2004);
    }

    function test_unknownChain_returnsZero() public view {
        assertEq(oracle.getParachainId("unknown"), 0);
    }

    // ─── Register Parachain ──────────────────────────────────────────

    function test_registerParachain() public {
        oracle.registerParachain("hydration", 2034);
        assertTrue(oracle.isParachainSupported(2034));
        assertEq(oracle.getParachainId("hydration"), 2034);
    }

    function test_registerParachain_byNonOwner_reverts() public {
        vm.prank(randomUser);
        vm.expectRevert(XcmOracle.Unauthorized.selector);
        oracle.registerParachain("hydration", 2034);
    }

    // ─── XCM Query Dispatch ──────────────────────────────────────────

    function test_dispatchAssetQuery_byOwner() public {
        oracle.dispatchAssetQuery(2000, "aDOT");
        assertTrue(oracle.queryDispatched(2000, "aDOT"));
    }

    function test_dispatchAssetQuery_byReporter() public {
        vm.prank(reporter);
        oracle.dispatchAssetQuery(2000, "aDOT");
        assertTrue(oracle.queryDispatched(2000, "aDOT"));
    }

    function test_dispatchAssetQuery_byRandom_reverts() public {
        vm.prank(randomUser);
        vm.expectRevert(XcmOracle.Unauthorized.selector);
        oracle.dispatchAssetQuery(2000, "aDOT");
    }

    function test_dispatchAssetQuery_unregistered_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(XcmOracle.ParachainNotRegistered.selector, 9999));
        oracle.dispatchAssetQuery(9999, "aDOT");
    }

    function test_dispatchAssetQuery_emitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit XcmQueryDispatched(2000, "aDOT", "");
        oracle.dispatchAssetQuery(2000, "aDOT");
    }

    // ─── Report Asset State ──────────────────────────────────────────

    function test_reportAssetState_byReporter() public {
        bytes32 hash = keccak256("state");
        address minter = makeAddr("minter");

        vm.prank(reporter);
        oracle.reportAssetState(2000, "aDOT", 50_000 ether, minter, hash);

        IXcmOracle.AssetState memory state = oracle.queryAssetState(2000, "aDOT");
        assertTrue(state.exists);
        assertEq(state.totalSupply, 50_000 ether);
        assertEq(state.minterAddress, minter);
        assertEq(state.stateHash, hash);
    }

    function test_reportAssetState_byRandom_reverts() public {
        vm.prank(randomUser);
        vm.expectRevert(XcmOracle.Unauthorized.selector);
        oracle.reportAssetState(2000, "aDOT", 50_000 ether, address(0), bytes32(0));
    }

    function test_reportAssetState_emitsEvent() public {
        vm.prank(reporter);
        vm.expectEmit(true, false, false, true);
        emit AssetStateReported(2000, "aDOT", 50_000 ether);
        oracle.reportAssetState(2000, "aDOT", 50_000 ether, address(0), bytes32(0));
    }

    // ─── Query Cached State ──────────────────────────────────────────

    function test_queryAssetState_empty() public view {
        IXcmOracle.AssetState memory state = oracle.queryAssetState(2000, "aDOT");
        assertFalse(state.exists);
    }

    function test_queryAssetState_unregistered_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(XcmOracle.ParachainNotRegistered.selector, 9999));
        oracle.queryAssetState(9999, "aDOT");
    }

    // ─── Full Flow: Dispatch -> Report -> Query ────────────────────────

    function test_fullFlow_dispatchThenReport() public {
        // 1. Owner dispatches query (XCM message sent to parachain)
        oracle.dispatchAssetQuery(2000, "aDOT");
        assertTrue(oracle.queryDispatched(2000, "aDOT"));

        // 2. Reporter reports response data (simulates XCM response)
        bytes32 hash = keccak256("aDOT_state");
        address minter = makeAddr("acalaMinter");
        vm.prank(reporter);
        oracle.reportAssetState(2000, "aDOT", 50_000 ether, minter, hash);

        // 3. queryDispatched should be cleared after report
        assertFalse(oracle.queryDispatched(2000, "aDOT"));

        // 4. Anyone can query cached state
        IXcmOracle.AssetState memory state = oracle.queryAssetState(2000, "aDOT");
        assertTrue(state.exists);
        assertEq(state.totalSupply, 50_000 ether);
        assertEq(state.minterAddress, minter);
    }

    // ─── Reporter Management ─────────────────────────────────────────

    function test_setReporter_authorize() public {
        address newReporter = makeAddr("newReporter");
        oracle.setReporter(newReporter, true);
        assertTrue(oracle.authorizedReporters(newReporter));
    }

    function test_setReporter_revoke() public {
        oracle.setReporter(reporter, false);
        assertFalse(oracle.authorizedReporters(reporter));
    }

    function test_setReporter_byNonOwner_reverts() public {
        vm.prank(randomUser);
        vm.expectRevert(XcmOracle.Unauthorized.selector);
        oracle.setReporter(makeAddr("x"), true);
    }

    // ─── XCM Precompile Address ──────────────────────────────────────

    function test_xcmPrecompileAddress() public view {
        assertEq(oracle.XCM_PRECOMPILE(), 0x00000000000000000000000000000000000a0000);
    }
}
