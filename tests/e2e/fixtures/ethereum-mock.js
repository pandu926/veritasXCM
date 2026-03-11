/**
 * Mock window.ethereum provider for Playwright E2E tests.
 * Compatible with ethers.js v6 BrowserProvider.
 */

const MOCK_ADDRESS = "0x742d35Cc6634C0532925a3b844Bc9e7595f2bD18";
const PASEO_CHAIN_ID_HEX = "0x190a35a1"; // 420420417

function injectEthereumMock() {
  window.ethereum = {
    isMetaMask: true,
    selectedAddress: null,
    chainId: PASEO_CHAIN_ID_HEX,
    networkVersion: "420420417",
    _events: {},

    request: async function ({ method, params }) {
      console.log("[MockEthereum]", method, params);
      switch (method) {
        case "eth_requestAccounts":
          this.selectedAddress = MOCK_ADDRESS;
          return [MOCK_ADDRESS];

        case "eth_accounts":
          return this.selectedAddress ? [this.selectedAddress] : [];

        case "eth_chainId":
          return PASEO_CHAIN_ID_HEX;

        case "net_version":
          return "420420417";

        case "wallet_switchEthereumChain":
          return null;

        case "wallet_addEthereumChain":
          return null;

        case "eth_getBalance":
          return "0x56bc75e2d63100000";

        case "eth_call": {
          // Mock registry.getVerificationResult response
          return (
            "0x" +
            "0000000000000000000000000000000000000000000000000000000000000055" +
            "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2" +
            "00000000000000000000000000000000000000000000003635c9adc5dea00000" +
            "0000000000000000000000000000000000000000000000000000000000000000"
          );
        }

        case "eth_sendTransaction":
          return "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890ab";

        case "eth_getTransactionReceipt":
          return {
            status: "0x1",
            blockNumber: "0x100",
            blockHash:
              "0x0000000000000000000000000000000000000000000000000000000000000000",
            transactionHash:
              params && params[0]
                ? params[0]
                : "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890ab",
            transactionIndex: "0x0",
            from: MOCK_ADDRESS,
            to: "0x6a141914Db10C0D3ccc00D5F9b970450f38F5863",
            gasUsed: "0x5208",
            cumulativeGasUsed: "0x5208",
            logs: [],
            logsBloom: "0x" + "0".repeat(512),
          };

        case "eth_blockNumber":
          return "0x100";

        case "eth_getBlockByNumber":
          return {
            number: "0x100",
            hash: "0x0000000000000000000000000000000000000000000000000000000000000000",
            timestamp:
              "0x" + Math.floor(Date.now() / 1000).toString(16),
            transactions: [],
          };

        case "eth_estimateGas":
          return "0x5208";

        case "eth_gasPrice":
        case "eth_maxPriorityFeePerGas":
          return "0x3b9aca00";

        case "eth_getCode":
          return "0x6060"; // Non-empty = contract exists

        case "eth_getTransactionCount":
          return "0x1";

        case "eth_feeHistory":
          return {
            baseFeePerGas: ["0x3b9aca00", "0x3b9aca00"],
            gasUsedRatio: [0.5],
            oldestBlock: "0xff",
            reward: [["0x3b9aca00"]],
          };

        default:
          console.log("[MockEthereum] Unhandled:", method);
          return null;
      }
    },

    on: function (event, callback) {
      if (!this._events[event]) this._events[event] = [];
      this._events[event].push(callback);
    },

    removeListener: function () {},
    removeAllListeners: function () {},
  };
}

if (typeof module !== "undefined") {
  module.exports = { injectEthereumMock, MOCK_ADDRESS };
}
