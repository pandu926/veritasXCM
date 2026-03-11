/**
 * Live wallet mock for Playwright E2E tests.
 * Injects window.ethereum that uses a real private key + real RPC.
 * This runs INSIDE the browser via page.addInitScript().
 */

function createLiveWalletMock(privateKey, address, rpcUrl, chainIdHex) {
  return `
    (function() {
      const PRIVATE_KEY = "${privateKey}";
      const ADDRESS = "${address}";
      const RPC_URL = "${rpcUrl}";
      const CHAIN_ID_HEX = "${chainIdHex}";

      // Wait for ethers to be available
      function waitForEthers(cb) {
        if (typeof ethers !== 'undefined') { cb(); return; }
        const interval = setInterval(() => {
          if (typeof ethers !== 'undefined') { clearInterval(interval); cb(); }
        }, 50);
      }

      waitForEthers(function() {
        const rpcProvider = new ethers.JsonRpcProvider(RPC_URL);
        const wallet = new ethers.Wallet(PRIVATE_KEY, rpcProvider);

        window.ethereum = {
          isMetaMask: true,
          selectedAddress: null,
          chainId: CHAIN_ID_HEX,
          networkVersion: String(parseInt(CHAIN_ID_HEX, 16)),
          _events: {},

          request: async function({ method, params }) {
            console.log('[LiveWalletMock]', method);
            switch (method) {
              case 'eth_requestAccounts':
                this.selectedAddress = ADDRESS;
                return [ADDRESS];

              case 'eth_accounts':
                return this.selectedAddress ? [this.selectedAddress] : [];

              case 'eth_chainId':
                return CHAIN_ID_HEX;

              case 'net_version':
                return this.networkVersion;

              case 'wallet_switchEthereumChain':
                return null;

              case 'wallet_addEthereumChain':
                return null;

              case 'eth_call':
                return await rpcProvider.send('eth_call', params);

              case 'eth_sendTransaction': {
                const txParams = params[0];
                const tx = await wallet.sendTransaction({
                  to: txParams.to,
                  data: txParams.data,
                  value: txParams.value || '0x0',
                  gasLimit: txParams.gas || undefined,
                });
                return tx.hash;
              }

              case 'eth_getTransactionReceipt':
                return await rpcProvider.send('eth_getTransactionReceipt', params);

              case 'eth_blockNumber':
                return await rpcProvider.send('eth_blockNumber', []);

              case 'eth_getBalance':
                return await rpcProvider.send('eth_getBalance', params);

              case 'eth_estimateGas':
                return await rpcProvider.send('eth_estimateGas', params);

              case 'eth_gasPrice':
                return await rpcProvider.send('eth_gasPrice', []);

              case 'eth_maxPriorityFeePerGas':
                try { return await rpcProvider.send('eth_maxPriorityFeePerGas', []); }
                catch { return '0x0'; }

              case 'eth_getCode':
                return await rpcProvider.send('eth_getCode', params);

              case 'eth_getTransactionCount':
                return await rpcProvider.send('eth_getTransactionCount', params);

              case 'eth_feeHistory':
                try { return await rpcProvider.send('eth_feeHistory', params); }
                catch { return { baseFeePerGas: ['0x0'], gasUsedRatio: [0], oldestBlock: '0x0' }; }

              case 'eth_getBlockByNumber':
                return await rpcProvider.send('eth_getBlockByNumber', params);

              default:
                console.log('[LiveWalletMock] Forwarding to RPC:', method);
                try { return await rpcProvider.send(method, params || []); }
                catch(e) { console.warn('[LiveWalletMock] RPC error:', method, e); return null; }
            }
          },

          on: function(event, callback) {
            if (!this._events[event]) this._events[event] = [];
            this._events[event].push(callback);
          },
          removeListener: function() {},
          removeAllListeners: function() {},
        };

        console.log('[LiveWalletMock] Injected successfully');
      });
    })();
  `;
}

module.exports = { createLiveWalletMock };
