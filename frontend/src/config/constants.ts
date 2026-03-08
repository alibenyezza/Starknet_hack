// Contract Addresses (Testnet Sepolia)
// v12: decimal fix (BTC=8, USDC=6), EkuboLPWrapper, GaugeController security
export const CONTRACTS = {
  // ── v12 (decimal fix + new contracts) ─────────────────────────────────────
  VAULT_MANAGER:        '0x07af1ee2343f2710ac9b7544f0714adf1df292e7e98fece42b3a3e64fe27a3e9',
  LT_TOKEN:             '0x018a65f5987d06a1e6d537a50ed7c8e4ea5869722f0f3772551e25f81efd4406',
  VIRTUAL_POOL:         '0x034bbd3d99c00f36773e712bbb8cba7022ee97746326cffda0af1c2efcb1a3c3',
  MOCK_EKUBO_ADAPTER:   '0x06c9c6ce0219d849675c1399a996908ced01aa8ec6660b09ab10bb2276908c48',
  MOCK_LENDING_ADAPTER: '0x0014c719633c27561470a0b507c4b1458766c6fa4d2b70f979679339e9edb3c7',

  // ── Tokens (v12 — new decimals: BTC=8, USDC=6) ──────────────────────────
  BTC_TOKEN:     '0x01299997532891f6cb0088b5c779138f98f29d5a03e23e9611fad7071dffd89b',
  USDC_TOKEN:    '0x02ada118d8ec35abdf936f2d2f93cbe0d4fc66bd16bb51ef3b4f2baf20d32306',

  // ── New v12 contracts ─────────────────────────────────────────────────────
  EKUBO_LP_WRAPPER:  '0x00d65a42e2aae825d3065a1693c5ede2e7ee31a1a7dfe8f44e9e1fb73e6f34bb',
  GAUGE_CONTROLLER:  '0x06a2b1f4a3e58cb0ad7a71f94e7fbfabd975f94863f68401c97019a4c0d567d2',
  FEE_DISTRIBUTOR:   '0x0' + '0'.repeat(62), // TODO: update after deploy_all.sh

  // ── v6 (kept for reference / Staker / LevAMM UI) ─────────────────────────
  LEVAMM:        '0x0623647a3e0f7f7a7aa0061a692c4e64e916dd853e0d71624da95f4076fff4af',
  STAKER:        '0x04620f57ef40e7e2293ca6d06153930697bcb88d173f1634ba5cff768acec273',
  SY_YB_TOKEN:   '0x0761c9f9d225c4b4e8e3f49ee5935af94a647e40f4c378a65c5553dfcd2efd4e', // sy-WBTC token
  SY_BTC_TOKEN:  '0x076cb4dadb2db9a95072ecffbb67a61076e642eced3d7f37361ff6f202018be3',
} as const;

// Network Configuration
export const NETWORK = {
  CHAIN_ID: '0x534e5f5345504f4c4941', // SN_SEPOLIA
  RPC_URL: 'https://api.cartridge.gg/x/starknet/sepolia', // proxied via /rpc in dev
  EXPLORER_URL: 'https://sepolia.voyager.online',
} as const;

// App Configuration
export const APP_CONFIG = {
  MIN_DEPOSIT: 0.001, // BTC
  MAX_DEPOSIT: 100, // BTC
  MIN_WITHDRAW: 0.001, // BTC
  REFRESH_INTERVAL: 15000, // 15 seconds
  SLIPPAGE_TOLERANCE: 0.5, // 0.5%
} as const;

// Health Factor Thresholds
export const HEALTH_FACTOR = {
  SAFE: 2.0,
  MODERATE: 1.5,
  WARNING: 1.2,
  DANGER: 1.0,
} as const;

// Token Decimals — v12: MockWBTC uses 8 decimals, MockUSDC uses 6
export const DECIMALS = {
  BTC: 8,
  USDC: 6,
  SHARES: 18,
} as const;

// Format Options
export const FORMAT = {
  BTC: {
    minimumFractionDigits: 4,
    maximumFractionDigits: 8,
  },
  USD: {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  },
  PERCENT: {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  },
} as const;
