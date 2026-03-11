// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AssetRegistry.sol";
import "../src/XcmAssetVerifier.sol";
import "../src/MockVerifierPrecompile.sol";
import "../src/MockXcmOracle.sol";
import "../src/XcmOracle.sol";

/// @title Deploy Script for VeritasXCM (Phase 3 — Real XCM)
/// @notice Supports both mock and real XCM oracle deployment
contract DeployScript is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        bool useRealXcm = vm.envOr("USE_REAL_XCM", false);

        vm.startBroadcast(deployerKey);

        // 1. Deploy precompile mock (for verification logic)
        MockVerifierPrecompile precompile = new MockVerifierPrecompile();

        // 2. Deploy oracle — real or mock
        address oracleAddress;
        if (useRealXcm) {
            XcmOracle realOracle = new XcmOracle();
            oracleAddress = address(realOracle);
            console.log("XcmOracle (REAL XCM) :", oracleAddress);
        } else {
            MockXcmOracle mockOracle = new MockXcmOracle();
            oracleAddress = address(mockOracle);
            console.log("MockXcmOracle (MOCK) :", oracleAddress);
        }

        // 3. Deploy registry
        AssetRegistry registry = new AssetRegistry();

        // 4. Deploy XcmAssetVerifier
        XcmAssetVerifier verifier = new XcmAssetVerifier(
            address(registry), address(precompile), oracleAddress
        );

        // 5. Authorize verifier
        registry.setVerifier(address(verifier));

        // 6. Whitelist minters
        verifier.setMinterWhitelist(address(0xACA1), true);
        verifier.setMinterWhitelist(address(0x1B7C), true);
        verifier.setMinterWhitelist(address(0xBF05), true);

        vm.stopBroadcast();

        // Summary
        console.log("");
        console.log("=== VeritasXCM Deployment Complete ===");
        console.log("Precompile  :", address(precompile));
        console.log("Oracle      :", oracleAddress);
        console.log("Registry    :", address(registry));
        console.log("Verifier    :", address(verifier));
        console.log("Owner       :", vm.addr(deployerKey));
        console.log("Mode        :", useRealXcm ? "REAL XCM" : "MOCK");
    }
}
