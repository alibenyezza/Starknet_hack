// Contract Addresses (Testnet Sepolia) — redeployed 2026-02-20 (fixed shares formula)
export const CONTRACTS = {
  VAULT_MANAGER: '0x02d74eea61e7d67bd9f3b54973bc9cd51d8a7526bc93168dce622647c630f83f',
  SY_BTC_TOKEN: '0x05cda6e0cf0c7656d76c61bfbd7d138532b6aa8245dbb070f50f015e689c2afd',
  BTC_TOKEN: '0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163', // MockWBTC with faucet
  USDC_TOKEN: '0x023e418680b7210d7e3c3307a5e02f4b326201dbd6b9bf0c28e95a4cedaecfeb', // MockUSDC with faucet
  EKUBO_POOL: '0x05fd7268228036c8237674709b699a732e7c2ae3c7d20ef1306950f3626610f9',   // MockEkuboAdapter
  VESU_LENDING: '0x0184b3fb971cd3ea627727c32e07b9a071bf4e68de42c61567f8d04ef80a474b', // MockLendingAdapter
  PRAGMA_ORACLE: '0x069751dd1f1d78907f361a725af5d06937e5c25839fcffaf898fbd1e79fd49c2', // MockPragmaAdapter
  LEVERAGE_MANAGER: '0x00bf47cb391843b4103b6c7dd5fdfea60dc8a39e10a7f980b32c1a66170567c7',
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
  USDC: 18, // MockUSDC uses 18 decimals (same as MockWBTC, for testnet math simplicity)
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
