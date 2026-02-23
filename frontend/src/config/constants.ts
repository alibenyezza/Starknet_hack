// Contract Addresses (Testnet Sepolia) — v5 deployments (fixed fallback, no double-counting)
export const CONTRACTS = {
  VAULT_MANAGER: '0x040489e90e3cafad2446fecb229bc06fea17f535788135469f12a15b983ef976',
  SY_BTC_TOKEN:  '0x076cb4dadb2db9a95072ecffbb67a61076e642eced3d7f37361ff6f202018be3',
  BTC_TOKEN:     '0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163', // MockWBTC faucet
  USDC_TOKEN:    '0x023e418680b7210d7e3c3307a5e02f4b326201dbd6b9bf0c28e95a4cedaecfeb',
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

// Token Decimals — MockWBTC uses 18 decimals (Cairo ERC20 default, not real BTC's 8)
export const DECIMALS = {
  BTC: 18,
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
