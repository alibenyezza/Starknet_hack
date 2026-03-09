// Contract Addresses (Testnet Sepolia)
// Full redeploy with fees, LEVAMM APR, rebalancing
export const CONTRACTS = {
  // ── Core vault contracts ─────────────────────────────────────
  VAULT_MANAGER:        '0x07eb052e36139c284835da8ac0591d7fb873a5e6779929575e373eb375ac38b8',
  LT_TOKEN:             '0x07bb2c643b849c46b845dec6488d9b3e0cffd3afe309b7e6f5c7ea45c6385a8f',
  VIRTUAL_POOL:         '0x0190f9b1eeef43f98b96bc0d4c8dc0b9b2c008013975b1b1061d8564a1cc4753',
  MOCK_EKUBO_ADAPTER:   '0x013a15529211d5a2775bd698609b379ca1ff70ffa65b8d5f81485b9837c0ee12',
  MOCK_LENDING_ADAPTER: '0x001b376346f9b24aca87c85c3a2780bea4941727fbc2a9e821b423d38cc4eb79',

  // ── Tokens (BTC=8 dec, USDC=6 dec) ──────────────────────────
  BTC_TOKEN:     '0x01299997532891f6cb0088b5c779138f98f29d5a03e23e9611fad7071dffd89b',
  USDC_TOKEN:    '0x02ada118d8ec35abdf936f2d2f93cbe0d4fc66bd16bb51ef3b4f2baf20d32306',

  // ── Fee & governance contracts ──────────────────────────────
  FEE_DISTRIBUTOR:   '0x0360f009cf2e29fb8a30e133cc7c32783409d341286560114ccff9e3c7fc7362',
  RISK_MANAGER:      '0x0481a49142bec3d6c68c77ec5ab1002c5f438aa55766c3efebbd741d35f25a25',
  EKUBO_LP_WRAPPER:  '0x07574ae39df29c66e2fc640966070630eaf16281c32aaa8dce4687fdf4400034',
  GAUGE_CONTROLLER:  '0x05d3800e8b1ee257b5f72ce0f4c373c5d8e5b9d84f1bff1917b073ce2fbe46e7',
  VOTING_ESCROW:     '0x0008617d29fed039d3448bdd002912183c45b6d4c268dbd33cf02055368eef3c',
  LIQUIDITY_GAUGE:   '0x0571bfcd77fee368783ff746f6ec0bf56706fc1989caa9c521295dfd97f72b13',

  // ── LEVAMM + Staker ─────────────────────────────────────────
  LEVAMM:        '0x007b1a0774303f1a9f5ead5ced7d67bf2ced3ecab52b9095501349b753b67a88',
  STAKER:        '0x01b92e5719bcf3c419113bbccb0e8ead3a93a8b5d38804edbcf26fcb7e06d719',
  SY_TOKEN:      '0x0761c9f9d225c4b4e8e3f49ee5935af94a647e40f4c378a65c5553dfcd2efd4e',
  SY_BTC_TOKEN:  '0x076cb4dadb2db9a95072ecffbb67a61076e642eced3d7f37361ff6f202018be3',
} as const;

// Network Configuration
export const NETWORK = {
  CHAIN_ID: '0x534e5f5345504f4c4941', // SN_SEPOLIA
  RPC_URL: 'https://api.cartridge.gg/x/starknet/sepolia',
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

// Token Decimals — MockWBTC uses 8 decimals, MockUSDC uses 6
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
