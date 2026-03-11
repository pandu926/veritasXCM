const express = require("express");
const path = require("path");
const { createProxyMiddleware } = require("http-proxy-middleware");

const app = express();
const PORT = 3333;
const RPC_URL = "https://eth-asset-hub-paseo.dotters.network";

// Proxy /rpc → Paseo RPC (bypasses CORS for browser)
app.use(
  "/rpc",
  createProxyMiddleware({
    target: RPC_URL,
    changeOrigin: true,
    pathRewrite: { "^/rpc": "/" },
  }),
);

// Serve frontend static files
app.use(express.static(path.join(__dirname, "../../../frontend")));

app.listen(PORT, () => {
  console.log(`Test server running at http://localhost:${PORT}`);
  console.log(`RPC proxy: http://localhost:${PORT}/rpc → ${RPC_URL}`);
});
