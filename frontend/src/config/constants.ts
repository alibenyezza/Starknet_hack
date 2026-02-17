// Contract Addresses (Testnet Sepolia)
export const CONTRACTS = {
  VAULT_MANAGER: '0x0000000000000000000000000000000000000000',
  SY_BTC_TOKEN: '0x0000000000000000000000000000000000000000',
  BTC_TOKEN: '0x0000000000000000000000000000000000000000',
  USDC_TOKEN: '0x0000000000000000000000000000000000000000',
  EKUBO_POOL: '0x0000000000000000000000000000000000000000',
  VESU_LENDING: '0x0000000000000000000000000000000000000000',
  PRAGMA_ORACLE: '0x0000000000000000000000000000000000000000',
} as const;

// Network Configuration
export const NETWORK = {
  CHAIN_ID: '0x534e5f5345504f4c4941', // SN_SEPOLIA
  RPC_URL: 'https://starknet-sepolia.public.blastapi.io',
  EXPLORER_URL: 'https://sepolia.starkscan.co',
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

// Token Decimals
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
