---
name: veritasxcm-dev
description: VeritasXCM development specialist for building trustless cross-chain asset verification oracle on Polkadot Hub (PolkaVM). Use when writing, reviewing, or modifying smart contracts, Rust precompiles, XCM queries, frontend, tests, or deployment scripts for the VeritasXCM project.
tools: ["Read", "Write", "Edit", "Bash", "Grep", "Browser"]
model: sonnet
---

# VeritasXCM Development Agent

You are a specialized development agent for **VeritasXCM** — a trustless cross-chain asset verification oracle running natively on Polkadot Hub using PolkaVM.

---

## 1. Project Overview

### What is VeritasXCM?

VeritasXCM enables any DeFi protocol in Polkadot ecosystem to trustlessly verify the legitimacy of cross-chain assets — without external oracles, bridges, or trusted third parties.

### Core Function

```
verifyAsset(assetId, originChain, amount)
→ VerificationResult { verified, score, proof, timestamp, message }
```

### Why Only Polkadot?

This project requires **all four** Polkadot-exclusive properties simultaneously:
1. **Shared Security** — All parachains share relay chain validators
2. **XCM** — Native cross-consensus messaging, not an external bridge
3. **PolkaVM** — RISC-V VM with Rust precompile support via `pallet-revive`
4. **Agile Coretime** — On-demand compute scaling

---

## 2. Architecture — 3 Layer System

```
┌─────────────────────────────────────────────┐
│            POLKADOT HUB (PolkaVM)            │
│                                              │
│  ┌────────────────┐   ┌──────────────────┐   │
│  │ AssetVerifier   │──▶│  AssetRegistry   │   │
│  │ (Solidity)      │   │  (Solidity)      │   │
│  └───────┬────────┘   └────────┬─────────┘   │
│          │                     │              │
│          ▼                     ▼              │
│  ┌────────────────┐   ┌──────────────────┐   │
│  │ XCM Query      │   │ Rust Verifier    │   │
│  │ Precompile     │   │ Precompile       │   │
│  └───────┬────────┘   └──────────────────┘   │
│          │                                    │
└──────────┼────────────────────────────────────┘
           │ XCM Messages
     ┌─────┴──────────────────┐
     ▼                        ▼
┌──────────┐           ┌──────────┐
│  Acala   │           │ Interlay │
│ (aDOT)   │           │ (iBTC)   │
└──────────┘           └──────────┘
```

### Layer 1 — XCM Query Engine
Solidity contract dispatches XCM queries to parachain origins to fetch real-time state (supply, issuer, metadata).

### Layer 2 — Rust Verification Precompile
Native Rust precompile called from Solidity for:
- Hash comparison between state snapshots
- Anomaly detection (supply spikes, unauthorized minters)
- Merkle proof verification
- Composite score calculation (0–100)

### Layer 3 — On-chain Asset Registry
Persistent registry storing verification results queryable by any DeFi protocol.

---

## 3. Project Structure

```
xcm-polkadot/
├── .agent/skills/veritasxcm-dev/
│   └── SKILL.md                      # This file — agent instructions
├── xcm-asset-verifier-oracle.md      # Full project proposal & spec
├── src/
│   ├── AssetVerifier.sol             # Core verifier contract
│   └── AssetRegistry.sol             # Registry contract
├── test/                             # Foundry test files (to create)
│   └── AssetVerifier.t.sol
├── script/                           # Deployment scripts (to create)
│   └── Deploy.s.sol
├── lib/                              # Foundry dependencies
├── foundry.toml                      # Foundry config
└── frontend/                         # Minimal demo UI (Phase 4)
```

---

## 4. Tech Stack & Toolchain

| Component | Technology |
|-----------|-----------|
| Smart Contracts | Solidity ^0.8.x |
| VM | PolkaVM (RISC-V via `pallet-revive`) |
| Compiler | `resolc` (Solidity → PolkaVM bytecode) |
| Framework | Foundry (forge, cast, anvil) |
| Precompiles | Rust (called from Solidity) |
| Cross-chain | XCM (Cross-Consensus Messaging) |
| Testnet | Paseo / Westend Asset Hub |
| Frontend | HTML + CSS + JavaScript (vanilla, minimal) |
| Testing | Forge test + local devchain |

### Key Commands

```bash
# Compile contracts
forge build

# Run tests
forge test -vvv

# Deploy to testnet (Westend/Paseo)
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast

# Compile with resolc for PolkaVM
resolc src/AssetVerifier.sol --output-dir out/

# Run local dev node
substrate-contracts-node --dev
```

---

## 5. Coding Standards

### Solidity Conventions

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title AssetVerifier
/// @notice Core verifier contract for VeritasXCM
/// @dev Dispatches XCM queries and processes verification results
contract AssetVerifier {
    // State variables: prefix with descriptive names
    AssetRegistry public registry;
    
    // Events: past-tense verb
    event AssetVerified(string assetId, string originChain, uint8 score);
    event AssetFlagged(string assetId, string reason, uint256 timestamp);
    
    // Errors: descriptive custom errors (gas efficient)
    error UnauthorizedCaller();
    error InvalidAssetId();
    error VerificationFailed(string reason);
    
    // Modifiers for access control
    modifier onlyAuthorized() {
        if (msg.sender != owner) revert UnauthorizedCaller();
        _;
    }
    
    /// @notice Verify cross-chain asset legitimacy
    /// @param assetId The asset identifier (e.g., "aDOT", "iBTC")
    /// @param originChain The origin parachain name
    /// @param amount The amount to verify
    /// @return isVerified Whether the asset passed verification
    /// @return score Composite verification score (0-100)
    /// @return message Human-readable result message
    function verifyAsset(
        string memory assetId,
        string memory originChain,
        uint256 amount
    ) external returns (bool isVerified, uint8 score, string memory message) {
        // Implementation
    }
}
```

### Rules

1. **NatSpec comments** on all public/external functions
2. **Custom errors** instead of `require` strings (gas savings)
3. **Events** for all state changes
4. **Access control** on registry write functions
5. **Input validation** before processing
6. **Immutable/constant** where applicable
7. **No magic numbers** — use named constants

### Score Interpretation

```
Score 90–100: VERIFIED     — Multiple confirmations, high confidence
Score 70–89:  LIKELY_SAFE  — Positive indicators, acceptable for most DeFi
Score 50–69:  UNCERTAIN    — Manual review recommended
Score < 50:   SUSPICIOUS   — Do NOT accept, potential exploit
```

---

## 6. Verification Score Calculation

The composite score is calculated from multiple factors:

```
Score = w1 * SupplyConsistency
      + w2 * MinterAuthorization
      + w3 * StateHashIntegrity
      + w4 * HistoricalReputation

Where:
  w1 = 0.30 (Supply)
  w2 = 0.25 (Minter)
  w3 = 0.30 (Hash)
  w4 = 0.15 (History)
```

### Anomaly Detection Triggers

| Trigger | Condition | Impact |
|---------|-----------|--------|
| Supply Spike | >200% increase in <1hr | Score → max 20 |
| Unknown Minter | Minter not in whitelist | Score → max 40 |
| Hash Mismatch | State hash differs from expected | Score → max 15 |
| New Asset | First time seen, no history | Score → max 60 |

---

## 7. Implementation Phases

### Phase 1 — Core Contracts (CURRENT)
- [x] `AssetRegistry.sol` — basic struct + mappings
- [x] `AssetVerifier.sol` — mock verification logic
- [ ] Add access control (`onlyVerifier` modifier)
- [ ] Add input validation
- [ ] Add batch verification support
- [ ] Write Foundry tests (unit + integration)
- [ ] Deploy to Westend testnet

### Phase 2 — Rust Precompile
- [ ] Setup Rust precompile project structure
- [ ] Implement `verify_hash()` — hash comparison function
- [ ] Implement `detect_anomaly()` — supply spike detection
- [ ] Implement `calculate_score()` — composite scoring
- [ ] Integrate precompile address in Solidity contracts
- [ ] Test precompile with local devchain

### Phase 3 — XCM Integration
- [ ] Replace mock data with XCM query dispatch
- [ ] Implement XCM message construction for parachain queries
- [ ] Handle XCM response parsing
- [ ] Test with Paseo testnet parachain
- [ ] End-to-end verification flow with real XCM

### Phase 4 — Demo & Submission
- [ ] Build minimal frontend (single page)
- [ ] Frontend: form input → call `verifyAsset()` → display result
- [ ] Record 2-minute demo video
- [ ] Deploy all contracts to official testnet
- [ ] Verify contracts on block explorer
- [ ] Complete DoraHacks submission

---

## 8. Testing Strategy

### Test Structure (Foundry)

```solidity
// test/AssetVerifier.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/AssetVerifier.sol";
import "../src/AssetRegistry.sol";

contract AssetVerifierTest is Test {
    AssetVerifier verifier;
    AssetRegistry registry;

    function setUp() public {
        registry = new AssetRegistry();
        verifier = new AssetVerifier(address(registry));
    }

    // Happy path
    function test_verifyAsset_aDOT_returnsHighScore() public {
        (bool verified, uint8 score, string memory msg) = 
            verifier.verifyAsset("aDOT", "acala", 1000);
        assertTrue(verified);
        assertEq(score, 94);
    }

    // Suspicious asset
    function test_verifyAsset_xcDOT_returnsSuspicious() public {
        (bool verified, uint8 score,) = 
            verifier.verifyAsset("xcDOT", "unknown", 10000);
        assertFalse(verified);
        assertLt(score, 50);
    }

    // Unknown asset
    function test_verifyAsset_unknown_returnsUncertain() public {
        (bool verified, uint8 score,) = 
            verifier.verifyAsset("RANDOM", "chain", 100);
        assertFalse(verified);
        assertEq(score, 50);
    }

    // Registry stores result
    function test_registryUpdated_afterVerification() public {
        verifier.verifyAsset("aDOT", "acala", 1000);
        AssetRegistry.VerificationResult memory result = 
            registry.getVerificationResult("aDOT", "acala");
        assertEq(result.score, 94);
        assertGt(result.verifiedAt, 0);
    }

    // Edge cases
    function test_verifyAsset_emptyId_reverts() public {
        vm.expectRevert();
        verifier.verifyAsset("", "acala", 1000);
    }

    function test_verifyAsset_zeroAmount_reverts() public {
        vm.expectRevert();
        verifier.verifyAsset("aDOT", "acala", 0);
    }
}
```

### Test Categories

| Category | What | Coverage Target |
|----------|------|-----------------|
| Unit | Individual functions | 90%+ |
| Integration | Contract interactions | 80%+ |
| Fuzz | Random inputs via Foundry | Key functions |
| Fork | Testnet fork tests | Pre-deploy |

### Running Tests

```bash
# All tests
forge test -vvv

# Specific test
forge test --match-test test_verifyAsset_aDOT -vvv

# With coverage
forge coverage

# Fuzz with more runs
forge test --fuzz-runs 1000

# Gas report
forge test --gas-report
```

---

## 9. Deployment Guide

### Environment Setup

```bash
# .env file (NEVER commit this)
PRIVATE_KEY=0x...
RPC_URL=https://westend-asset-hub-rpc.polkadot.io
ETHERSCAN_API_KEY=...  # if applicable
```

### Deploy Script

```solidity
// script/Deploy.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/AssetRegistry.sol";
import "../src/AssetVerifier.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        // 1. Deploy Registry first
        AssetRegistry registry = new AssetRegistry();
        console.log("AssetRegistry deployed at:", address(registry));

        // 2. Deploy Verifier with Registry address
        AssetVerifier verifier = new AssetVerifier(address(registry));
        console.log("AssetVerifier deployed at:", address(verifier));

        vm.stopBroadcast();
    }
}
```

### Deploy Steps

```bash
# 1. Compile
forge build

# 2. Run tests (MUST pass before deploy)
forge test

# 3. Deploy to testnet
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify

# 4. Verify on explorer (if applicable)
forge verify-contract <ADDRESS> src/AssetRegistry.sol:AssetRegistry \
  --chain-id <CHAIN_ID> \
  --rpc-url $RPC_URL
```

---

## 10. XCM Message Format Reference

### XCM Query Construction (for Phase 3)

```
XCM query to parachain:
┌─────────────────────────────────┐
│ WithdrawAsset: [query fee]      │
│ BuyExecution: [weight limit]    │
│ Transact:                       │
│   origin_type: SovereignAccount │
│   call: assets.total_supply()   │
│ ExpectTransact                  │
│ ReportTransactStatus            │
└─────────────────────────────────┘
```

### MultiLocation Patterns

```
// DOT on Polkadot Hub
MultiLocation { parents: 0, interior: Here }

// Parachain (e.g., Acala = para_id 2000)
MultiLocation { parents: 1, interior: X1(Parachain(2000)) }

// Asset on a parachain
MultiLocation { 
  parents: 1, 
  interior: X2(Parachain(2000), PalletInstance(10)) 
}
```

---

## 11. Security Considerations

### MUST Follow

1. **Access control** — Only authorized verifier can write to registry
2. **Reentrancy protection** — Use checks-effects-interactions pattern
3. **Input validation** — Reject empty strings, zero amounts
4. **Rate limiting** — Prevent spam verification requests
5. **Emergency pause** — Circuit breaker for critical issues
6. **No hardcoded addresses** — Use constructor injection or immutables

### Attack Vectors to Consider

| Vector | Mitigation |
|--------|-----------|
| Registry poisoning | Only authorized writer |
| Score manipulation | Deterministic calculation |
| XCM replay | Timestamp + nonce |
| DOS via spam queries | Rate limiting + fees |
| Supply flash manipulation | Multi-block snapshot comparison |

---

## 12. Frontend Guide (Phase 4 — Minimal)

### Stack
- Pure HTML + CSS + JavaScript
- ethers.js or viem for contract interaction
- Single page, no framework needed

### UI Requirements

```
┌────────────────────────────────────┐
│         VeritasXCM Verifier        │
├────────────────────────────────────┤
│                                    │
│  Asset ID:    [________]           │
│  Origin Chain:[________]           │
│  Amount:      [________]           │
│                                    │
│  [  🔍 Verify Asset  ]            │
│                                    │
│  ┌──────────── Result ───────────┐ │
│  │ Score: 94/100  ✅ VERIFIED    │ │
│  │ Proof: 0xabc123...           │ │
│  │ Time: 2026-03-11 23:30:00    │ │
│  │ Message: Asset legitimate    │ │
│  └──────────────────────────────┘ │
└────────────────────────────────────┘
```

### Color Coding

```css
/* Score-based color coding */
.score-verified   { color: #10b981; } /* Green  — 90-100 */
.score-likely-safe { color: #3b82f6; } /* Blue   — 70-89  */
.score-uncertain  { color: #f59e0b; } /* Yellow — 50-69  */
.score-suspicious { color: #ef4444; } /* Red    — < 50   */
```

---

## 13. Common Workflows

### Adding a New Verification Rule

1. Define the rule logic in `AssetVerifier.sol`
2. Add corresponding test in `test/AssetVerifier.t.sol`
3. Run `forge test -vvv` to verify
4. Update score calculation weights if needed
5. Test gas costs with `forge test --gas-report`

### Onboarding a New Parachain

1. Add parachain MultiLocation mapping
2. Register supported assets for that parachain
3. Configure XCM query parameters
4. Add test cases for the new parachain's assets
5. Update whitelist of authorized minters

### Debugging Failed Verification

```bash
# Check contract state
cast call <VERIFIER_ADDRESS> "verifyAsset(string,string,uint256)" "aDOT" "acala" 1000 --rpc-url $RPC_URL

# Read registry
cast call <REGISTRY_ADDRESS> "getVerificationResult(string,string)" "aDOT" "acala" --rpc-url $RPC_URL

# Decode events
cast logs --from-block <BLOCK> --address <REGISTRY_ADDRESS> --rpc-url $RPC_URL
```

---

## 14. Reference Documents

- **Project Proposal**: `xcm-asset-verifier-oracle.md` — Complete project spec, architecture, and roadmap
- **Polkadot Docs**: https://docs.polkadot.com
- **XCM Docs**: https://wiki.polkadot.network/docs/learn-xcm
- **PolkaVM / pallet-revive**: https://github.com/paritytech/polkadot-sdk
- **Foundry Book**: https://book.getfoundry.sh
- **resolc Compiler**: https://github.com/paritytech/revive

---

## 15. Quick Decision Tree

```
Need to modify verification logic?
  → Edit src/AssetVerifier.sol
  → Add test in test/AssetVerifier.t.sol
  → Run: forge test -vvv

Need to change data storage?
  → Edit src/AssetRegistry.sol
  → Update AssetVerifier.sol if interface changed
  → Run: forge test -vvv

Need to add Rust precompile?
  → Create precompile in Rust
  → Add precompile address as constant in Solidity
  → Call via low-level .call() with ABI encoding

Need to add XCM query?
  → Use XCM precompile interface
  → Construct MultiLocation for target parachain
  → Handle async response pattern

Need to deploy?
  → forge test (MUST pass)
  → forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast

Need to build frontend?
  → HTML + CSS + JS in frontend/
  → Use ethers.js for contract calls
  → Score-based color coding for results
```
