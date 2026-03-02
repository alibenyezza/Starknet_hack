// Contract Addresses (Testnet Sepolia)
// v5: VaultManager + SyBtcToken
// v6: Factory + LevAMM + VirtualPool + Staker + SyYbToken
// v7: YieldBasis rewrite — LtToken + new MockEkubo/Lending + VirtualPool + VaultManager
//   → Deploy with scripts/deploy_v7.sh, then fill in the v7 addresses below
export const CONTRACTS = {
  // ── v7 (YieldBasis — deploy with scripts/deploy_v7.sh) ───────────────────
  VAULT_MANAGER:        '0x0797a73712b6555e8bb9ddb2ac9fa78a7de9035ee83b496865e756b85c2cbf1b',
  LT_TOKEN:             '0x0329ea731410c3544d93a8f7326201634b02f76d146ce572709ae410d6756c47',
  VIRTUAL_POOL:         '0x0460d5b3cf27cbf296495c22301badd05a68c50c416036c7ed33c5454eed5f55',
  MOCK_EKUBO_ADAPTER:   '0x01f46c9c60dca701db51acfdbd17279145f56446d979ec93d1c63a564b18e1a5',
  MOCK_LENDING_ADAPTER: '0x01d3c4293e6e7a5de4284947d8ba07b64c026e1da7b535d41439e929f13140a1',

  // ── Tokens (stable, reused from v5/v6) ───────────────────────────────────
  BTC_TOKEN:     '0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163',
  USDC_TOKEN:    '0x023e418680b7210d7e3c3307a5e02f4b326201dbd6b9bf0c28e95a4cedaecfeb',

  // ── v6 (kept for reference / Staker / LevAMM UI) ─────────────────────────
  FACTORY:       '0x0253d30100bd7cbbc2bf146bdddcbb4adfc0cae0dc3d2a3ab172a1b4e21c8780',
  LEVAMM:        '0x0623647a3e0f7f7a7aa0061a692c4e64e916dd853e0d71624da95f4076fff4af',
  STAKER:        '0x04620f57ef40e7e2293ca6d06153930697bcb88d173f1634ba5cff768acec273',
  SY_YB_TOKEN:   '0x0761c9f9d225c4b4e8e3f49ee5935af94a647e40f4c378a65c5553dfcd2efd4e',
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
