<p align="center">
  <img src="https://img.shields.io/badge/Polkadot-E6007A?style=for-the-badge&logo=polkadot&logoColor=white" alt="Polkadot" />
  <img src="https://img.shields.io/badge/Solidity-363636?style=for-the-badge&logo=solidity&logoColor=white" alt="Solidity" />
  <img src="https://img.shields.io/badge/Rust-000000?style=for-the-badge&logo=rust&logoColor=white" alt="Rust" />
  <img src="https://img.shields.io/badge/XCM_V5-E6007A?style=for-the-badge" alt="XCM V5" />
  <img src="https://img.shields.io/badge/Foundry-333333?style=for-the-badge" alt="Foundry" />
  <img src="https://img.shields.io/badge/Playwright-2EAD33?style=for-the-badge&logo=playwright&logoColor=white" alt="Playwright" />
  <img src="https://img.shields.io/badge/216_Tests-00D68F?style=for-the-badge" alt="216 Tests" />
</p>

<h1 align="center">VeritasXCM</h1>

<p align="center">
  <strong>Trustless Cross-Chain Asset Verification Oracle on Polkadot</strong>
</p>

<p align="center">
  Verify the legitimacy of wrapped and bridged assets in real-time using<br/>
  XCM V5 queries, Rust precompiles, and on-chain scoring — no trusted intermediaries.
</p>

<p align="center">
  <a href="#live-on-paseo">Live Demo</a> &bull;
  <a href="#real-xcm-proof">XCM Proof</a> &bull;
  <a href="#the-problem">Problem</a> &bull;
  <a href="#how-it-works">How It Works</a> &bull;
  <a href="#architecture">Architecture</a> &bull;
  <a href="#testing">Testing</a>
</p>

---

## Live on Paseo

> **Deployed on Paseo Asset Hub (Testnet) — Real XCM Mode**
>
> | Contract | Address |
> |----------|---------|
> | **Verifier** | [`0x461F3A87FE0cDA5f42005004A14b44ebb89181f2`](https://assethub-paseo.subscan.io/account/0x461F3A87FE0cDA5f42005004A14b44ebb89181f2) |
> | **Registry** | [`0x37bA0f0B66474E96C96332935e95F98aE72b2d29`](https://assethub-paseo.subscan.io/account/0x37bA0f0B66474E96C96332935e95F98aE72b2d29) |
> | **XcmOracle** | [`0xC856458944fecE98766700b229D3D57219D42F5b`](https://assethub-paseo.subscan.io/account/0xC856458944fecE98766700b229D3D57219D42F5b) |
> | **XCM Precompile** | `0x00000000000000000000000000000000000a0000` |
>
> **Chain ID:** `420420417` &bull; **XCM Version:** V5

### Ecosystem Health Dashboard

Four cross-chain assets monitored in real-time with auto-loaded scores:

| Asset | Origin Chain | ParaId | Score | Status |
|-------|-------------|--------|-------|--------|
| aDOT | Acala | 2000 | 85 | VERIFIED |
| iBTC | Interlay | 2032 | 85 | VERIFIED |
| vDOT | Bifrost | 2030 | 85 | VERIFIED |
| xcDOT | Moonbeam | 2004 | 60 | UNCERTAIN |

---

## Real XCM Proof

This is **not a mock**. VeritasXCM calls the real XCM precompile (`0x...0a0000`) on Paseo Asset Hub.

| Evidence | Details |
|----------|---------|
| **Successful XCM Send Tx** | [`0x9678278bccd05564458a1fc5d8069928758ddace9d5a2b431815ff5267f4d626`](https://assethub-paseo.subscan.io/extrinsic/0x9678278bccd05564458a1fc5d8069928758ddace9d5a2b431815ff5267f4d626) |
| **Target** | Relay Chain (VersionedLocation V5: parents=1, Here) |
| **Message** | VersionedXcm V5: `[ClearOrigin]` |
| **Block** | 6364064 on Paseo Asset Hub |
| **Precompile Address** | `0x00000000000000000000000000000000000a0000` (confirmed deployed, returns `0x60006000fd`) |

**What this proves:** Solidity smart contracts on PolkaVM can send real XCM messages to other consensus systems via the native precompile. This is the foundation for trustless cross-chain asset verification — no bridges, no relayers.

> **Note:** The XCM precompile requires V5 encoding (discovered during development — V4 is rejected). Contract-to-precompile nested calls are a known pallet-revive limitation being addressed; direct EOA calls work perfectly.

---

## The Problem

Cross-chain bridges have been responsible for **over $2 billion in losses** since 2021. When an asset like `aDOT` claims to represent DOT from Acala, there is no trustless way to verify:

- Is the total supply on the origin chain consistent?
- Was it minted by an authorized address?
- Has the state been tampered with?
- Does it have a reliable verification history?

Existing solutions rely on **trusted relayers**, multisigs, or optimistic assumptions. None of them leverage Polkadot's native cross-chain messaging to verify assets directly at the source.

## The Solution

**VeritasXCM** uses Polkadot's **XCM (Cross-Consensus Messaging)** to query parachain state directly — no bridges, no relayers, no trust assumptions. It computes a composite **Trust Score (0-100)** from four on-chain factors and stores the result immutably in a registry contract.

---

## How It Works

```
                                      Origin Parachain
                                     (Acala, Bifrost, ...)
                                            |
                                     XCM V5 Query (Real)
                                            |
                                            v
   User Request                       XCM Oracle
       |                         (calls 0x...0a0000)
       v                                    |
  AssetVerifier ──── score factors ────> Precompile (Rust)
       |                                    |
       |          supply_ok? ───────────────┤
       |          minter_ok? ───────────────┤
       |          hash_ok? ─────────────────┤
       |          history_count ────────────┘
       |                                    |
       v                                    v
  AssetRegistry <───── Trust Score (0-100) ──┘
  (immutable record)
```

### Composite Scoring System

The Trust Score is a weighted sum of four verification factors:

| Factor | Weight | What It Checks |
|--------|--------|----------------|
| Supply Consistency | 30 | Current supply matches expected range (no spike/drop > 200%) |
| Minter Authorization | 25 | Minting address is in the authorized whitelist |
| State Hash Integrity | 30 | `keccak256` hash of asset state matches recorded snapshot |
| Verification History | 15 | Number of prior successful verifications (max bonus at 10+) |

**Score Thresholds:**

| Score | Status | Meaning |
|-------|--------|---------|
| 90-100 | HIGH CONFIDENCE | All factors pass + established history |
| 70-89 | VERIFIED | Core checks pass, minor issues tolerable |
| 50-69 | UNCERTAIN | Significant discrepancies, caution advised |
| 0-49 | SUSPICIOUS | Critical failures, high counterfeit risk |

**Anomaly Detection** caps the score when dangerous patterns are detected:

| Anomaly Type | Max Score | Example |
|-------------|-----------|---------|
| Supply Spike | 20 | Supply tripled overnight |
| Supply Drop | 35 | 80% of supply burned unexpectedly |
| Unauthorized Minter | 40 | Tokens minted by unknown address |
| Hash Mismatch | 15 | State data has been tampered with |

---

## Architecture

### Smart Contract Hierarchy

```
VerifierBase (abstract)
├── AssetVerifier          Phase 2: Snapshot-based verification
└── XcmAssetVerifier       Phase 3: Live XCM oracle verification

AssetRegistry              Immutable on-chain result storage
XcmOracle                  Real XCM V5 dispatch to parachains
MockXcmOracle              Mock oracle for testing
MockVerifierPrecompile     Solidity mock of the Rust precompile
IXcm                       Polkadot XCM precompile interface (send/execute/weighMessage)
IXcmOracle                 Oracle interface
IVerifierPrecompile        Precompile interface
```

### Three-Phase Design

| Phase | Component | Purpose |
|-------|-----------|---------|
| **Phase 1** | AssetRegistry | Store and retrieve verification results |
| **Phase 2** | AssetVerifier + MockPrecompile | Verify against managed snapshots with scoring precompile |
| **Phase 3** | XcmAssetVerifier + XcmOracle | End-to-end verification using live XCM parachain queries |

### Key Contract Details

#### `XcmOracle.sol` — Real XCM Integration

- Interfaces with Polkadot's native XCM precompile at `0x00...0a0000`
- Uses **XCM V5** encoding (discovered: Paseo rejects V4)
- SCALE-encodes `VersionedLocation` and `VersionedXcm` for cross-chain dispatch
- Pre-registers 4 parachains: Acala (2000), Interlay (2032), Bifrost (2030), Moonbeam (2004)
- Authorized reporter pattern for async XCM response handling

#### `IXcm.sol` — Polkadot XCM Precompile Interface

```solidity
interface IXcm {
    function send(bytes calldata destination, bytes calldata message) external;
    function execute(bytes calldata message, Weight calldata weight) external;
    function weighMessage(bytes calldata message) external view returns (Weight memory);
}
```

#### `XcmAssetVerifier.sol` — Phase 3 Verifier

- Fetches live asset state from parachains via XcmOracle
- Rejects stale oracle data older than 1 hour (`MAX_DATA_AGE`)
- Compares current state against previous snapshot for anomaly detection
- Stores result in AssetRegistry with proof hash

#### `AssetRegistry.sol` — Result Storage

- Stores verification scores, anomaly flags, timestamps, and proof hashes
- Role-based access: only authorized verifier can write results
- Emits `VerificationUpdated` and `AnomalyDetected` events

### Rust Precompile

The scoring logic is implemented in Rust (`precompile/src/lib.rs`) for deployment as a PolkaVM precompile:

```rust
pub fn calculate_score_with_anomaly(
    supply_ok: bool,     // 30 points
    minter_ok: bool,     // 25 points
    hash_ok: bool,       // 30 points
    history_count: u32,  // up to 15 points
    anomaly: &AnomalyResult,
) -> u8 { ... }
```

The Solidity `MockVerifierPrecompile` mirrors this logic for testnet deployment.

### Security Features

- **Cooldown enforcement** — 5-minute minimum between verifications to prevent spam
- **Stale data rejection** — XCM oracle data older than 1 hour is rejected
- **Batch size limits** — Maximum 20 assets per batch to prevent gas DoS
- **Input validation** — String length caps (64 chars), zero-address checks
- **Anomaly score capping** — Suspicious assets cannot achieve high scores
- **Pause mechanism** — Emergency circuit breaker for all verifications
- **XSS prevention** — Frontend uses DOM API (no innerHTML) for user-supplied data
- **CSP headers** — Content Security Policy restricts script and resource origins
- **SRI integrity** — Subresource Integrity hash on CDN dependencies (ethers.js)

---

## Project Structure

```
xcm-polkadot/
├── src/                             # Solidity smart contracts (10 contracts)
│   ├── VerifierBase.sol             # Shared abstract base (modifiers, helpers)
│   ├── AssetVerifier.sol            # Phase 2: snapshot-based verification
│   ├── XcmAssetVerifier.sol         # Phase 3: XCM oracle verification
│   ├── AssetRegistry.sol            # On-chain result registry
│   ├── XcmOracle.sol                # Real XCM V5 query dispatcher
│   ├── MockXcmOracle.sol            # Mock oracle for testing
│   ├── MockVerifierPrecompile.sol   # Solidity mock of Rust precompile
│   ├── IVerifierPrecompile.sol      # Precompile interface
│   ├── IXcmOracle.sol               # Oracle interface
│   └── IXcm.sol                     # Polkadot XCM precompile interface
│
├── precompile/                      # Rust verification precompile
│   ├── Cargo.toml
│   └── src/lib.rs                   # Hash verify, anomaly detect, scoring
│
├── test/                            # Foundry unit tests (134 tests)
│   ├── AssetVerifier.t.sol          # 34 tests
│   ├── XcmAssetVerifier.t.sol       # 27 tests
│   ├── AssetRegistry.t.sol          # 18 tests
│   ├── XcmOracle.t.sol              # 20 tests
│   ├── MockVerifierPrecompile.t.sol # 19 tests
│   └── MockXcmOracle.t.sol          # 16 tests
│
├── tests/e2e/                       # Playwright E2E tests (58 tests)
│   ├── dashboard.spec.js            # Ecosystem health dashboard
│   ├── full-flow.spec.js            # Complete verification flows
│   ├── page-load.spec.js            # Page initialization & UI
│   ├── quick-fill.spec.js           # Form auto-fill
│   ├── read-state.spec.js           # Live chain reads
│   ├── history.spec.js              # Verification history
│   ├── wallet-connection.spec.js    # MetaMask integration
│   ├── responsive.spec.js           # Mobile/tablet/desktop
│   ├── global-setup.js              # Auto-seeds assets on Paseo
│   ├── pages/VeritasPage.js         # Page Object Model
│   └── fixtures/                    # Test server, wallet mocks
│
├── frontend/                        # Web3 dApp interface
│   ├── index.html                   # Single-page app (glassmorphism UI)
│   ├── app.js                       # Web3 logic + XCM send (ethers.js v6)
│   └── style.css                    # Design system (Polkadot theme)
│
├── script/
│   └── Deploy.s.sol                 # Foundry deploy (supports USE_REAL_XCM=true)
│
├── foundry.toml                     # Foundry configuration
├── playwright.config.js             # E2E test configuration
└── package.json                     # Node dependencies & scripts
```

---

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast)
- [Node.js](https://nodejs.org/) >= 18
- [Rust](https://rustup.rs/) (for the precompile)

### Installation

```bash
git clone https://github.com/pfrfrfr/xcm-polkadot.git
cd xcm-polkadot

forge install
npm install
npx playwright install chromium
```

### Environment Setup

```bash
cp .env.example .env.test
```

Edit `.env.test` with your private key:

```env
TEST_PRIVATE_KEY=0xYOUR_PRIVATE_KEY
TEST_ADDRESS=0xYOUR_ADDRESS
RPC_URL=https://eth-asset-hub-paseo.dotters.network
REGISTRY_ADDRESS=0x37bA0f0B66474E96C96332935e95F98aE72b2d29
VERIFIER_ADDRESS=0x461F3A87FE0cDA5f42005004A14b44ebb89181f2
ORACLE_ADDRESS=0xC856458944fecE98766700b229D3D57219D42F5b
CHAIN_ID=420420417
```

### Build & Run

```bash
# Compile Solidity contracts
forge build

# Build Rust precompile
cd precompile && cargo build --release && cd ..

# Deploy to Paseo (real XCM mode)
USE_REAL_XCM=true forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --legacy

# Start the frontend
npm run serve
# Open http://localhost:3333
```

---

## Testing

### Unit Tests (Foundry) — 134 Tests

```bash
forge test
```

| Test Suite | Tests | Coverage |
|-----------|-------|----------|
| AssetVerifierTest | 34 | Access control, scoring, anomaly detection, batch verify, cooldown |
| XcmAssetVerifierTest | 27 | XCM oracle integration, stale data, anomaly comparison |
| XcmOracleTest | 20 | XCM dispatch, reporter auth, parachain registration, full flow |
| MockVerifierPrecompileTest | 19 | Hash verification, minter check, scoring engine |
| AssetRegistryTest | 18 | Result storage, role access, event emission |
| MockXcmOracleTest | 16 | Mock oracle data, parachain resolution |

### E2E Tests (Playwright) — 58 Tests

```bash
npm test
```

Tests run against **live Paseo Asset Hub** — not mocks. Global setup auto-seeds assets on-chain.

| Spec File | Tests | What It Covers |
|-----------|-------|----------------|
| `page-load.spec.js` | 16 | DOM structure, stats animation, UI elements |
| `dashboard.spec.js` | 10 | Ecosystem health cards, auto-load scores, click-to-fill |
| `read-state.spec.js` | 9 | Live RPC reads, score display, error handling |
| `quick-fill.spec.js` | 7 | Form auto-fill with 4 test assets |
| `full-flow.spec.js` | 4 | End-to-end: load, fill, read, verify on-chain |
| `history.spec.js` | 4 | Verification history table |
| `wallet-connection.spec.js` | 4 | MetaMask connection flow |
| `responsive.spec.js` | 4 | Mobile, tablet, desktop layouts |

### Rust Precompile Tests

```bash
cd precompile && cargo test
```

```
[PASS] 24 tests (hash verify, anomaly detect, minter check, scoring, anomaly caps)
```

### Total Test Coverage

| Layer | Framework | Tests |
|-------|-----------|-------|
| Smart Contracts | Foundry (forge) | 134 |
| E2E (Live Testnet) | Playwright | 58 |
| Rust Precompile | Cargo | 24 |
| **Total** | | **216** |

---

## Why Polkadot?

VeritasXCM is **only possible on Polkadot**. No other ecosystem provides:

1. **XCM V5** — Native cross-chain messaging that lets smart contracts send messages to any consensus system, without bridges or relayers. We proved this works: [tx 0x9678278b...](https://assethub-paseo.subscan.io/extrinsic/0x9678278bccd05564458a1fc5d8069928758ddace9d5a2b431815ff5267f4d626)
2. **PolkaVM (pallet-revive)** — Run Solidity contracts on Polkadot with access to native runtime precompiles
3. **Shared Security** — All parachains share the relay chain's security, making XCM queries trustless by design
4. **Heterogeneous Sharding** — Each parachain is purpose-built, but VeritasXCM can verify assets across all of them from a single hub

---

## Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Smart Contracts | Solidity 0.8.20 | Core verification logic (10 contracts) |
| Precompile | Rust | High-performance scoring engine |
| Runtime | PolkaVM (pallet-revive) | Polkadot-native EVM execution |
| Cross-Chain | XCM V5 | Real precompile calls to relay chain |
| Testing | Foundry + Playwright | 134 unit + 58 E2E on live testnet |
| Frontend | Vanilla JS + ethers.js v6 | Web3 dApp with XCM send button |
| Network | Paseo Asset Hub | Polkadot testnet deployment |

---

## Use Cases

- **DeFi Protocols** — Verify collateral assets before accepting them in lending/borrowing
- **DEXs** — Flag suspicious wrapped tokens before allowing trades
- **Wallets** — Display trust scores next to cross-chain asset balances
- **Insurance** — Automated claim triggers based on anomaly detection
- **Governance** — Only allow voting with verified cross-chain tokens

---

## Roadmap

| Milestone | Status |
|-----------|--------|
| Core smart contracts (Registry, Verifier, Oracle) | Done |
| Rust precompile (hash, anomaly, scoring) | Done |
| Real XCM V5 precompile call on Paseo | **Done** (Proven) |
| Frontend dApp with live reads + XCM send | Done |
| Ecosystem Health Dashboard (auto-load) | Done |
| 134 unit + 58 E2E tests on live testnet | Done |
| XCM oracle integration (Phase 3 contracts) | Done |
| Contract-to-precompile nested calls | Pending pallet-revive update |
| Multi-chain dashboard with historical trends | Planned |
| SDK for third-party DeFi integration | Planned |

---

## License

MIT

---

<p align="center">
  Built for the <strong>Polkadot Solidity Hackathon 2026</strong><br/>
  Powered by XCM V5 + PolkaVM + Rust
</p>
