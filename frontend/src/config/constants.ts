// Contract Addresses (Testnet Sepolia)
export const CONTRACTS = {
  VAULT_MANAGER: '0x01b24b14b91b59930a71ca6f84da7dcb1883e576f4d6fdceecc8194099a228ca',
  SY_BTC_TOKEN: '0x03184feec0a8d5ce9e7d2a282568996322ce04b81301179379a7343c03c0b7be',
  BTC_TOKEN: '0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163', // MockWBTC with faucet
  USDC_TOKEN: '0x0000000000000000000000000000000000000000000000000000000000000002',
  EKUBO_POOL: '0x0000000000000000000000000000000000000000',
  VESU_LENDING: '0x0000000000000000000000000000000000000000',
  PRAGMA_ORACLE: '0x0000000000000000000000000000000000000000',
} as const;

// Network Configuration
export const NETWORK = {
  CHAIN_ID: '0x534e5f5345504f4c4941', // SN_SEPOLIA
  RPC_URL: 'https://api.cartridge.gg/x/starknet/sepolia',
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
  BTC: 18, // MockWBTC uses DefaultConfig (18 decimals)
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
