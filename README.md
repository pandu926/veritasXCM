<p align="center">
  <img src="https://img.shields.io/badge/Polkadot-E6007A?style=for-the-badge&logo=polkadot&logoColor=white" alt="Polkadot" />
  <img src="https://img.shields.io/badge/Solidity-363636?style=for-the-badge&logo=solidity&logoColor=white" alt="Solidity" />
  <img src="https://img.shields.io/badge/Rust-000000?style=for-the-badge&logo=rust&logoColor=white" alt="Rust" />
  <img src="https://img.shields.io/badge/Foundry-333333?style=for-the-badge" alt="Foundry" />
  <img src="https://img.shields.io/badge/Playwright-2EAD33?style=for-the-badge&logo=playwright&logoColor=white" alt="Playwright" />
</p>

<h1 align="center">VeritasXCM</h1>

<p align="center">
  <strong>Trustless Cross-Chain Asset Verification Oracle on Polkadot</strong>
</p>

<p align="center">
  Verify the legitimacy of wrapped and bridged assets in real-time using<br/>
  XCM queries, Rust precompiles, and on-chain scoring — no trusted intermediaries.
</p>

<p align="center">
  <a href="#live-demo">Live Demo</a> &bull;
  <a href="#the-problem">Problem</a> &bull;
  <a href="#how-it-works">How It Works</a> &bull;
  <a href="#architecture">Architecture</a> &bull;
  <a href="#getting-started">Getting Started</a> &bull;
  <a href="#testing">Testing</a>
</p>

---

## Live Demo

> **Deployed on Paseo Asset Hub (Testnet)**
> - **Chain ID:** `420420417`
> - **Registry:** [`0x9A340E7eeDA37623556A566473648365dfe390E1`](https://assethub-paseo.subscan.io/account/0x9A340E7eeDA37623556A566473648365dfe390E1)
> - **Verifier:** [`0xBb1Df6990CCCd16c32939c8E30fb38A9D2cFC820`](https://assethub-paseo.subscan.io/account/0xBb1Df6990CCCd16c32939c8E30fb38A9D2cFC820)

Four test assets are verified on-chain with real scores:

| Asset | Origin Chain | Score | Status |
|-------|-------------|-------|--------|
| aDOT | Acala | 85 | VERIFIED |
| iBTC | Interlay | 85 | VERIFIED |
| vDOT | Bifrost | 85 | VERIFIED |
| xcDOT | Moonbeam | 60 | UNCERTAIN |

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
                                        XCM Query
                                            |
                                            v
   User Request                       XCM Oracle
       |                              (on-chain)
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
XcmOracle                  Dispatches XCM queries to parachains
MockVerifierPrecompile     Solidity mock of the Rust precompile
```

### Three-Phase Design

| Phase | Component | Purpose |
|-------|-----------|---------|
| **Phase 1** | AssetRegistry | Store and retrieve verification results |
| **Phase 2** | AssetVerifier + MockPrecompile | Verify against managed snapshots with scoring precompile |
| **Phase 3** | XcmAssetVerifier + XcmOracle | End-to-end verification using live XCM parachain queries |

### Contract Details

#### `VerifierBase.sol` — Shared Foundation

Abstract contract providing common logic to both verifiers:

- **Constants:** `ANOMALY_THRESHOLD_PCT = 200`, `SCORE_VERIFIED = 70`, `MAX_BATCH_SIZE = 20`, `VERIFICATION_COOLDOWN = 5 min`
- **Input Validation:** Asset ID length, origin chain length, amount > 0
- **Score Interpretation:** Maps numeric score to human-readable message
- **Anomaly Caps:** Limits score ceiling when anomalies are detected
- **Access Control:** `onlyOwner`, `whenNotPaused` modifiers

#### `AssetVerifier.sol` — Snapshot Verifier (Phase 2)

- Owner registers asset snapshots (supply, minter, state hash)
- Tracks `previousSupply` for anomaly comparison across verifications
- Delegates hash verification, anomaly detection, and scoring to precompile
- Supports batch verification of up to 20 assets per call
- Enforces 5-minute cooldown between verifications per asset

#### `XcmAssetVerifier.sol` — XCM Oracle Verifier (Phase 3)

- Fetches live asset state from parachains via XcmOracle
- Rejects stale oracle data older than 1 hour (`MAX_DATA_AGE`)
- Compares current state against previous snapshot for anomaly detection
- Stores result in AssetRegistry with proof hash

#### `AssetRegistry.sol` — Result Storage

- Stores verification scores, anomaly flags, timestamps, and proof hashes
- Role-based access: only authorized verifier can write results
- Emits `VerificationUpdated` and `AnomalyDetected` events

#### `XcmOracle.sol` — XCM Bridge

- Interfaces with Polkadot's native XCM precompile at `0x00...0a0000`
- Pre-registers parachains: Acala (2000), Interlay (2032), Bifrost (2030), Moonbeam (2004)
- Asynchronous: dispatches query, receives callback with asset state

### Rust Precompile

The scoring logic is implemented in Rust (`precompile/src/lib.rs`) for deployment as a PolkaVM precompile:

```rust
// Score calculation with anomaly-aware capping
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
- **SRI integrity** — Subresource Integrity hash on CDN dependencies

---

## Project Structure

```
xcm-polkadot/
├── src/                             # Solidity smart contracts
│   ├── VerifierBase.sol             # Shared abstract base (modifiers, helpers)
│   ├── AssetVerifier.sol            # Phase 2: snapshot-based verification
│   ├── XcmAssetVerifier.sol         # Phase 3: XCM oracle verification
│   ├── AssetRegistry.sol            # On-chain result registry
│   ├── XcmOracle.sol                # Real XCM query dispatcher
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
├── tests/e2e/                       # Playwright E2E tests (48 tests)
│   ├── full-flow.spec.js            # Complete verification flows
│   ├── page-load.spec.js            # Page initialization
│   ├── quick-fill.spec.js           # Form auto-fill
│   ├── read-state.spec.js           # Live chain reads
│   ├── history.spec.js              # Verification history
│   ├── wallet-connection.spec.js    # MetaMask integration
│   ├── responsive.spec.js           # Responsive layout
│   ├── global-setup.js              # Auto-seeds assets on Paseo
│   ├── pages/VeritasPage.js         # Page Object Model
│   └── fixtures/                    # Test server, wallet mocks
│
├── frontend/                        # Web3 dApp interface
│   ├── index.html                   # Single-page app (glassmorphism UI)
│   ├── app.js                       # Web3 logic (ethers.js v6)
│   └── style.css                    # Design system (Polkadot theme)
│
├── scripts/
│   └── seed-assets.js               # Seed test assets on Paseo
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
# Clone the repository
git clone https://github.com/pfrfrfr/xcm-polkadot.git
cd xcm-polkadot

# Install Foundry dependencies
forge install

# Install Node dependencies
npm install

# Install Playwright browsers
npx playwright install chromium
```

### Environment Setup

```bash
cp .env.example .env.test
```

Edit `.env.test` with your values:

```env
TEST_PRIVATE_KEY=0xYOUR_PRIVATE_KEY
TEST_ADDRESS=0xYOUR_ADDRESS
RPC_URL=https://eth-asset-hub-paseo.dotters.network
REGISTRY_ADDRESS=0x9A340E7eeDA37623556A566473648365dfe390E1
VERIFIER_ADDRESS=0xBb1Df6990CCCd16c32939c8E30fb38A9D2cFC820
CHAIN_ID=420420417
```

### Build

```bash
# Compile Solidity contracts
forge build

# Build Rust precompile
cd precompile && cargo build --release
```

### Run the Frontend

```bash
# Start the dev server with RPC proxy (avoids CORS)
npm run serve
# Open http://localhost:3333
```

---

## Testing

### Unit Tests (Foundry) — 134 Tests

```bash
forge test
```

```
[PASS] 134 tests across 6 test suites
```

Covers all contracts: access control, scoring logic, anomaly detection, batch verification, cooldown enforcement, stale data rejection, input validation, and edge cases.

### E2E Tests (Playwright) — 48 Tests

```bash
# Run all E2E tests against live Paseo testnet
npm test
```

```
[PASS] 48 tests across 7 spec files
```

Tests run against **live Paseo Asset Hub** — not mocks. The global setup automatically verifies that test assets are seeded on-chain before tests begin.

| Spec File | Tests | What It Covers |
|-----------|-------|----------------|
| `full-flow.spec.js` | 4 | End-to-end: load, fill, read, verify on-chain |
| `page-load.spec.js` | 14 | DOM structure, stats, UI elements |
| `quick-fill.spec.js` | 7 | Form auto-fill with test assets |
| `read-state.spec.js` | 6 | Live RPC reads from Paseo |
| `history.spec.js` | 4 | Verification history display |
| `wallet-connection.spec.js` | 4 | MetaMask connection flow |
| `responsive.spec.js` | 4 | Mobile, tablet, desktop layouts |

### Rust Precompile Tests

```bash
cd precompile && cargo test
```

```
[PASS] 24 tests (hash, anomaly, minter, score, anomaly caps)
```

### Total Test Coverage

| Layer | Framework | Tests |
|-------|-----------|-------|
| Smart Contracts | Foundry (forge) | 134 |
| E2E (Live Testnet) | Playwright | 48 |
| Rust Precompile | Cargo | 24 |
| **Total** | | **206** |

---

## Why Polkadot?

VeritasXCM is **only possible on Polkadot**. No other ecosystem provides:

1. **XCM** — Native cross-chain messaging that lets smart contracts query parachain state directly, without bridges or relayers
2. **PolkaVM (pallet-revive)** — Run Solidity contracts on Polkadot with Rust precompile support
3. **Shared Security** — All parachains share the relay chain's security, making XCM queries trustless
4. **Heterogeneous Sharding** — Each parachain is purpose-built, but VeritasXCM can verify assets across all of them from a single hub

---

## Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Smart Contracts | Solidity 0.8.20 | Core verification logic |
| Precompile | Rust | High-performance scoring engine |
| Runtime | PolkaVM (pallet-revive) | Polkadot-native EVM execution |
| Cross-Chain | XCM | Trustless parachain queries |
| Testing | Foundry + Playwright | Unit + E2E on live testnet |
| Frontend | Vanilla JS + ethers.js v6 | Web3 dApp interface |
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
| Core smart contracts (Registry, Verifier) | Done |
| Rust precompile (hash, anomaly, scoring) | Done |
| Mock oracle + testnet deployment | Done |
| Frontend dApp with live reads | Done |
| 134 unit tests + 48 E2E tests on live testnet | Done |
| XCM oracle integration (Phase 3 contracts) | Done |
| Real XCM precompile activation on PolkaVM | Pending Runtime Support |
| Multi-chain dashboard with historical trends | Planned |
| SDK for third-party DeFi integration | Planned |

---

## License

MIT

---

<p align="center">
  Built for the <strong>Polkadot Solidity Hackathon 2026</strong><br/>
  Powered by XCM + PolkaVM + Rust
</p>
