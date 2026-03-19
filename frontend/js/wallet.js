/* ===================================================================
   VeritasXCM -- Wallet Connection
   =================================================================== */

// --- Shared state ---
var readOnlyProvider = new ethers.JsonRpcProvider(RPC_URL);
var provider;
var signer;
var userAddress;

// --- Wallet Connection ---
async function connectWallet() {
  if (typeof window.ethereum !== "undefined") {
    try {
      provider = new ethers.BrowserProvider(window.ethereum);

      // Switch to Paseo Network
      try {
        await window.ethereum.request({
          method: "wallet_switchEthereumChain",
          params: [{ chainId: "0x" + PASEO_CHAIN_ID.toString(16) }],
        });
      } catch (switchError) {
        if (switchError.code === 4902) {
          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [
              {
                chainId: "0x" + PASEO_CHAIN_ID.toString(16),
                chainName: "Paseo Asset Hub (pallet-revive)",
                rpcUrls: [DIRECT_RPC],
                nativeCurrency: { name: "PAS", symbol: "PAS", decimals: 18 },
              },
            ],
          });
        } else {
          throw switchError;
        }
      }

      signer = await provider.getSigner();
      userAddress = await signer.getAddress();

      document.getElementById("connectWalletBtn").classList.add("hidden");
      document.getElementById("connectedState").classList.remove("hidden");
      document.getElementById("statusText").innerText =
        userAddress.substring(0, 6) + "..." + userAddress.substring(38);
    } catch (_error) {
      showError("Connection failed. Please check MetaMask console.");
    }
  } else {
    showError(
      "Please install MetaMask or another Web3 wallet to submit transactions.",
    );
  }
}
