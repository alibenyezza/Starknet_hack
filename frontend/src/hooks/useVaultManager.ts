/**
 * useVaultManager — connects the UI to the StarkYield contracts on Sepolia.
 *
 * Reads:  RpcProvider + Contract class (starknet.js handles u256 encoding)
 * Writes: account.execute (wallet required)
 */

import { useState, useEffect, useCallback, useMemo } from 'react';
import { useAccount } from '@starknet-react/core';
import { RpcProvider, Contract, uint256 } from 'starknet';
import { CONTRACTS, APP_CONFIG } from '@/config/constants';

// ── Utility: detect undeployed placeholder address ────────────────────────
const ZERO_ADDR = '0x' + '0'.repeat(63);
function isDeployed(addr: string): boolean {
  return addr !== ZERO_ADDR && addr !== '0x0';
}

// ── ABIs (minimal — only what we call) ────────────────────────────────────

const ERC20_ABI = [
  {
    type: 'function',
    name: 'balance_of',
    inputs: [{ name: 'account', type: 'core::starknet::contract_address::ContractAddress' }],
    outputs: [{ type: 'core::integer::u256' }],
    state_mutability: 'view',
  },
  {
    type: 'function',
    name: 'balanceOf',
    inputs: [{ name: 'account', type: 'core::starknet::contract_address::ContractAddress' }],
    outputs: [{ type: 'core::integer::u256' }],
    state_mutability: 'view',
  },
] as const;

const VAULT_ABI = [
  { type: 'function', name: 'get_total_assets',    inputs: [], outputs: [{ type: 'core::integer::u256' }], state_mutability: 'view' },
  { type: 'function', name: 'get_share_price',     inputs: [], outputs: [{ type: 'core::integer::u256' }], state_mutability: 'view' },
  { type: 'function', name: 'get_health_factor',   inputs: [], outputs: [{ type: 'core::integer::u256' }], state_mutability: 'view' },
  { type: 'function', name: 'get_current_leverage',inputs: [], outputs: [{ type: 'core::integer::u256' }], state_mutability: 'view' },
  { type: 'function', name: 'get_btc_price',       inputs: [], outputs: [{ type: 'core::integer::u256' }], state_mutability: 'view' },
  {
    type: 'function',
    name: 'get_user_shares',
    inputs: [{ name: 'user', type: 'core::starknet::contract_address::ContractAddress' }],
    outputs: [{ type: 'core::integer::u256' }],
    state_mutability: 'view',
  },
] as const;

const LEVAMM_ABI = [
  { type: 'function', name: 'get_x0',            inputs: [], outputs: [{ type: 'core::integer::u256' }], state_mutability: 'view' },
  { type: 'function', name: 'get_dtv',           inputs: [], outputs: [{ type: 'core::integer::u256' }], state_mutability: 'view' },
  { type: 'function', name: 'is_over_levered',   inputs: [], outputs: [{ type: 'core::bool' }],         state_mutability: 'view' },
  { type: 'function', name: 'is_under_levered',  inputs: [], outputs: [{ type: 'core::bool' }],         state_mutability: 'view' },
  { type: 'function', name: 'is_active',         inputs: [], outputs: [{ type: 'core::bool' }],         state_mutability: 'view' },
  { type: 'function', name: 'get_collateral_value', inputs: [], outputs: [{ type: 'core::integer::u256' }], state_mutability: 'view' },
  { type: 'function', name: 'get_debt',          inputs: [], outputs: [{ type: 'core::integer::u256' }], state_mutability: 'view' },
  { type: 'function', name: 'get_current_btc_price', inputs: [], outputs: [{ type: 'core::integer::u256' }], state_mutability: 'view' },
  {
    type: 'function', name: 'get_price',
    inputs: [{ name: 'btc_amount', type: 'core::integer::u256' }],
    outputs: [{ type: 'core::integer::u256' }],
    state_mutability: 'view',
  },
  {
    type: 'function', name: 'swap',
    inputs: [{ name: 'direction', type: 'core::bool' }, { name: 'btc_amount', type: 'core::integer::u256' }],
    outputs: [{ type: 'core::integer::u256' }],
    state_mutability: 'external',
  },
  { type: 'function', name: 'accrue_interest', inputs: [], outputs: [], state_mutability: 'external' },
] as const;

const VIRTUAL_POOL_ABI = [
  { type: 'function', name: 'can_rebalance',              inputs: [], outputs: [{ type: 'core::bool' }],         state_mutability: 'view' },
  { type: 'function', name: 'get_imbalance_direction',    inputs: [], outputs: [{ type: 'core::bool' }],         state_mutability: 'view' },
  { type: 'function', name: 'get_total_profit_distributed', inputs: [], outputs: [{ type: 'core::integer::u256' }], state_mutability: 'view' },
  { type: 'function', name: 'get_last_rebalance_block',   inputs: [], outputs: [{ type: 'core::integer::u64' }], state_mutability: 'view' },
  { type: 'function', name: 'rebalance',                  inputs: [], outputs: [{ type: 'core::integer::u256' }], state_mutability: 'external' },
] as const;

const STAKER_ABI = [
  { type: 'function', name: 'get_total_staked',       inputs: [], outputs: [{ type: 'core::integer::u256' }], state_mutability: 'view' },
  {
    type: 'function', name: 'get_staked_balance',
    inputs: [{ name: 'user', type: 'core::starknet::contract_address::ContractAddress' }],
    outputs: [{ type: 'core::integer::u256' }],
    state_mutability: 'view',
  },
  {
    type: 'function', name: 'pending_rewards',
    inputs: [{ name: 'user', type: 'core::starknet::contract_address::ContractAddress' }],
    outputs: [{ type: 'core::integer::u256' }],
    state_mutability: 'view',
  },
  {
    type: 'function', name: 'stake',
    inputs: [{ name: 'sy_btc_amount', type: 'core::integer::u256' }],
    outputs: [],
    state_mutability: 'external',
  },
  {
    type: 'function', name: 'unstake',
    inputs: [{ name: 'sy_btc_amount', type: 'core::integer::u256' }],
    outputs: [],
    state_mutability: 'external',
  },
  { type: 'function', name: 'claim_rewards', inputs: [], outputs: [{ type: 'core::integer::u256' }], state_mutability: 'external' },
] as const;

// ── helpers ────────────────────────────────────────────────────────────────

/**
 * Safely convert whatever starknet.js returns for a u256 into a bigint.
 * starknet.js v6 may return: bigint | { low: bigint; high: bigint } | string
 */
function toBigInt(val: unknown): bigint {
  if (val === undefined || val === null) return 0n;
  if (typeof val === 'bigint') return val;
  if (typeof val === 'number') return BigInt(Math.floor(val));
  if (typeof val === 'string') return BigInt(val);
  // u256 struct { low, high }
  if (typeof val === 'object' && 'low' in (val as object) && 'high' in (val as object)) {
    const u = val as { low: bigint; high: bigint };
    return uint256.uint256ToBN({ low: u.low, high: u.high });
  }
  return 0n;
}

function fromWei(raw: unknown, decimals = 18): number {
  const n = toBigInt(raw);
  if (n === 0n) return 0;
  return Number(n) / 10 ** decimals;
}

function toWei(amount: number, decimals = 18): bigint {
  // String-based conversion avoids float64 precision loss for large values (e.g. 8 BTC = 8e18)
  const fixed = amount.toFixed(decimals);
  const [int, frac = ''] = fixed.split('.');
  return BigInt(int + frac.padEnd(decimals, '0').slice(0, decimals));
}

function u256Calldata(value: bigint): [string, string] {
  const low  = value & ((1n << 128n) - 1n);
  const high = value >> 128n;
  return [low.toString(), high.toString()];
}

// ── hook ───────────────────────────────────────────────────────────────────

export interface VaultStats {
  totalAssets:   number;
  sharePrice:    number;
  healthFactor:  number;
  leverage:      number;
  vaultBtcPrice: number;
}

export function useVaultManager() {
  const { account, address } = useAccount();

  // Use direct RPC URL so it works both in dev and on Vercel production.
  // In dev, Vite also proxies /rpc, but the direct URL avoids that dependency.
  const rpc = useMemo(() => new RpcProvider({ nodeUrl: 'https://api.cartridge.gg/x/starknet/sepolia', blockIdentifier: 'latest' }), []);

  // Contract instances
  const btcContract         = useMemo(() => new Contract(ERC20_ABI       as any, CONTRACTS.BTC_TOKEN,     rpc), [rpc]);
  const vaultContract       = useMemo(() => new Contract(VAULT_ABI       as any, CONTRACTS.VAULT_MANAGER, rpc), [rpc]);
  const levammContract      = useMemo(() => new Contract(LEVAMM_ABI      as any, CONTRACTS.LEVAMM,        rpc), [rpc]);
  const virtualPoolContract = useMemo(() => new Contract(VIRTUAL_POOL_ABI as any, CONTRACTS.VIRTUAL_POOL,  rpc), [rpc]);
  const stakerContract      = useMemo(() => new Contract(STAKER_ABI      as any, CONTRACTS.STAKER,        rpc), [rpc]);

  // ── state ──────────────────────────────────────────────────────────────
  const [wbtcBalance,    setWbtcBalance]    = useState(0);
  const [userDepositBTC, setUserDepositBTC] = useState(0);
  const [userShares,     setUserShares]     = useState(0n);

  const [stats, setStats] = useState<VaultStats>({
    totalAssets: 0, sharePrice: 1, healthFactor: 0, leverage: 0, vaultBtcPrice: 96000,
  });

  const [isLoading,     setIsLoading]     = useState(false);
  const [isDepositing,  setIsDepositing]  = useState(false);
  const [isWithdrawing,  setIsWithdrawing]  = useState(false);
  const [isFauceting,    setIsFauceting]    = useState(false);
  const [isRebalancing,  setIsRebalancing]  = useState(false);

  // ── LEVAMM / VirtualPool / Staker state ───────────────────────────────
  const [levammStats, setLevammStats] = useState({
    dtv: 0,
    x0: 0,
    collateralValue: 0,
    debt: 0,
    isOverLevered: false,
    isUnderLevered: false,
    isInitialized: false,
    canRebalance: false,
    totalProfit: 0,
  });
  const [stakerStats, setStakerStats] = useState({
    totalStaked: 0,
    userStaked: 0,
    pendingRewards: 0,
  });
  const [isSwapping,            setIsSwapping]            = useState(false);
  const [isVirtualRebalancing,  setIsVirtualRebalancing]  = useState(false);
  const [isStaking,             setIsStaking]             = useState(false);
  const [isUnstaking,           setIsUnstaking]           = useState(false);
  const [isClaimingRewards,     setIsClaimingRewards]     = useState(false);

  // ── refresh ────────────────────────────────────────────────────────────

  const refresh = useCallback(async () => {
    setIsLoading(true);

    // ── Vault-level stats — isolated so oracle errors don't block wBTC balance ──
    let priceBn = 0n;
    try {
      const [assets, price, hf, lev, btcRaw] = await Promise.all([
        vaultContract.get_total_assets(),
        vaultContract.get_share_price(),
        vaultContract.get_health_factor(),
        vaultContract.get_current_leverage(),
        vaultContract.get_btc_price(),
      ]);
      priceBn = toBigInt(price);
      setStats({
        totalAssets:   fromWei(assets),
        sharePrice:    fromWei(price),
        healthFactor:  fromWei(hf),
        leverage:      fromWei(lev),
        vaultBtcPrice: fromWei(btcRaw),
      });
    } catch (err) {
      console.error('[useVaultManager] vault stats error:', err);
    }

    // ── User-specific reads — always run, independent of oracle ──
    if (address) {
      try {
        const [btcBal, shares] = await Promise.all([
          btcContract.balance_of(address),
          vaultContract.get_user_shares(address),
        ]);
        const balBn    = toBigInt(btcBal);
        const sharesBn = toBigInt(shares);
        setWbtcBalance(fromWei(balBn));
        setUserShares(sharesBn);
        const depositBTC = sharesBn === 0n || priceBn === 0n
          ? 0
          : Number(sharesBn * priceBn / (10n ** 18n)) / 10 ** 18;
        setUserDepositBTC(depositBTC);
      } catch (err) {
        console.error('[useVaultManager] user balance error:', err);
      }
    }

    // ── LEVAMM + VirtualPool stats — only if deployed ──
    if (isDeployed(CONTRACTS.LEVAMM)) {
      try {
        const [dtv, x0, overLevered, underLevered, active, collateral, debt] = await Promise.all([
          levammContract.get_dtv(),
          levammContract.get_x0(),
          levammContract.is_over_levered(),
          levammContract.is_under_levered(),
          levammContract.is_active(),
          levammContract.get_collateral_value(),
          levammContract.get_debt(),
        ]);
        const [canRebal, totalProfit] = await Promise.all([
          virtualPoolContract.can_rebalance(),
          virtualPoolContract.get_total_profit_distributed(),
        ]);
        setLevammStats({
          dtv:             fromWei(dtv),
          x0:              fromWei(x0),
          collateralValue: fromWei(collateral),
          debt:            fromWei(debt),
          isOverLevered:   Boolean(overLevered),
          isUnderLevered:  Boolean(underLevered),
          isInitialized:   Boolean(active),
          canRebalance:    Boolean(canRebal),
          totalProfit:     fromWei(totalProfit),
        });
      } catch (err) {
        console.error('[useVaultManager] levamm stats error:', err);
      }
    }

    // ── Staker stats — only if deployed + user connected ──
    if (isDeployed(CONTRACTS.STAKER)) {
      try {
        const total = await stakerContract.get_total_staked();
        setStakerStats(prev => ({ ...prev, totalStaked: fromWei(total) }));
        if (address) {
          const [userStaked, pending] = await Promise.all([
            stakerContract.get_staked_balance(address),
            stakerContract.pending_rewards(address),
          ]);
          setStakerStats({
            totalStaked:    fromWei(total),
            userStaked:     fromWei(userStaked),
            pendingRewards: fromWei(pending),
          });
        }
      } catch (err) {
        console.error('[useVaultManager] staker stats error:', err);
      }
    }

    setIsLoading(false);
  }, [address, btcContract, vaultContract, levammContract, virtualPoolContract, stakerContract]);

  useEffect(() => {
    refresh();
    const id = setInterval(refresh, APP_CONFIG.REFRESH_INTERVAL);
    return () => clearInterval(id);
  }, [refresh]);

  // ── write actions ──────────────────────────────────────────────────────

  const faucet = useCallback(async (): Promise<{ success: boolean; txHash?: string; error?: string }> => {
    if (!account) return { success: false, error: 'Wallet not connected' };
    setIsFauceting(true);
    try {
      const [low, high] = u256Calldata(toWei(1));
      const tx = await account.execute([{
        contractAddress: CONTRACTS.BTC_TOKEN,
        entrypoint: 'faucet',
        calldata: [low, high],
      }]);
      setTimeout(refresh, 5000);  // first refresh ~5s after tx
      setTimeout(refresh, 12000); // second refresh ~12s (Starknet can be slow)
      return { success: true, txHash: tx.transaction_hash };
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error('[useVaultManager] faucet error:', msg);
      return { success: false, error: msg };
    } finally {
      setIsFauceting(false);
    }
  }, [account, refresh]);

  const deposit = useCallback(async (
    btcAmount: number,
  ): Promise<{ success: boolean; txHash?: string; error?: string }> => {
    if (!account)       return { success: false, error: 'Wallet not connected' };
    if (btcAmount <= 0) return { success: false, error: 'Amount must be > 0' };
    setIsDepositing(true);
    try {
      const [low, high] = u256Calldata(toWei(btcAmount));
      const tx = await account.execute([
        {
          contractAddress: CONTRACTS.BTC_TOKEN,
          entrypoint: 'approve',
          calldata: [CONTRACTS.VAULT_MANAGER, low, high],
        },
        {
          contractAddress: CONTRACTS.VAULT_MANAGER,
          entrypoint: 'deposit',
          calldata: [low, high],
        },
      ]);
      setTimeout(refresh, 4000);
      return { success: true, txHash: tx.transaction_hash };
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error('[useVaultManager] deposit error:', msg);
      return { success: false, error: msg };
    } finally {
      setIsDepositing(false);
    }
  }, [account, refresh]);

  const withdraw = useCallback(async (
    btcAmount?: number,
  ): Promise<{ success: boolean; txHash?: string; error?: string }> => {
    if (!account)          return { success: false, error: 'Wallet not connected' };
    if (userShares === 0n) return { success: false, error: 'No shares to withdraw' };

    // Convert BTC amount → shares proportionally: shares = btcAmount / sharePrice
    let sharesToWithdraw: bigint;
    if (btcAmount !== undefined && btcAmount > 0 && stats.sharePrice > 0) {
      sharesToWithdraw = toWei(btcAmount / stats.sharePrice);
      if (sharesToWithdraw > userShares) sharesToWithdraw = userShares;
    } else {
      sharesToWithdraw = userShares;
    }

    setIsWithdrawing(true);
    try {
      const [low, high] = u256Calldata(sharesToWithdraw);
      const tx = await account.execute([{
        contractAddress: CONTRACTS.VAULT_MANAGER,
        entrypoint: 'withdraw',
        calldata: [low, high],
      }]);
      setTimeout(refresh, 4000);
      return { success: true, txHash: tx.transaction_hash };
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error('[useVaultManager] withdraw error:', msg);
      return { success: false, error: msg };
    } finally {
      setIsWithdrawing(false);
    }
  }, [account, userShares, stats.sharePrice, refresh]);

  const rebalance = useCallback(async (): Promise<{ success: boolean; txHash?: string; error?: string }> => {
    if (!account) return { success: false, error: 'Wallet not connected' };
    setIsRebalancing(true);
    try {
      const tx = await account.execute([{
        contractAddress: CONTRACTS.VAULT_MANAGER,
        entrypoint: 'rebalance',
        calldata: [],
      }]);
      setTimeout(refresh, 4000);
      return { success: true, txHash: tx.transaction_hash };
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error('[useVaultManager] rebalance error:', msg);
      return { success: false, error: msg };
    } finally {
      setIsRebalancing(false);
    }
  }, [account, refresh]);

  // ── LEVAMM swap ────────────────────────────────────────────────────────
  const levammSwap = useCallback(async (
    direction: boolean,
    btcAmount: number,
  ): Promise<{ success: boolean; txHash?: string; error?: string }> => {
    if (!account) return { success: false, error: 'Wallet not connected' };
    setIsSwapping(true);
    try {
      const [low, high] = u256Calldata(toWei(btcAmount));
      const tx = await account.execute([{
        contractAddress: CONTRACTS.LEVAMM,
        entrypoint: 'swap',
        calldata: [direction ? '1' : '0', low, high],
      }]);
      setTimeout(refresh, 4000);
      return { success: true, txHash: tx.transaction_hash };
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error('[useVaultManager] levamm swap error:', msg);
      return { success: false, error: msg };
    } finally {
      setIsSwapping(false);
    }
  }, [account, refresh]);

  // ── VirtualPool rebalance ───────────────────────────────────────────────
  const virtualRebalance = useCallback(async (): Promise<{ success: boolean; txHash?: string; error?: string }> => {
    if (!account) return { success: false, error: 'Wallet not connected' };
    setIsVirtualRebalancing(true);
    try {
      const tx = await account.execute([{
        contractAddress: CONTRACTS.VIRTUAL_POOL,
        entrypoint: 'rebalance',
        calldata: [],
      }]);
      setTimeout(refresh, 4000);
      return { success: true, txHash: tx.transaction_hash };
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error('[useVaultManager] virtualRebalance error:', msg);
      return { success: false, error: msg };
    } finally {
      setIsVirtualRebalancing(false);
    }
  }, [account, refresh]);

  // ── Staker actions ─────────────────────────────────────────────────────
  const stakeShares = useCallback(async (
    amount: number,
  ): Promise<{ success: boolean; txHash?: string; error?: string }> => {
    if (!account) return { success: false, error: 'Wallet not connected' };
    setIsStaking(true);
    try {
      const [low, high] = u256Calldata(toWei(amount));
      const tx = await account.execute([
        // Approve Staker to pull syBTC
        { contractAddress: CONTRACTS.SY_BTC_TOKEN, entrypoint: 'approve', calldata: [CONTRACTS.STAKER, low, high] },
        { contractAddress: CONTRACTS.STAKER,       entrypoint: 'stake',   calldata: [low, high] },
      ]);
      setTimeout(refresh, 4000);
      return { success: true, txHash: tx.transaction_hash };
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error('[useVaultManager] stakeShares error:', msg);
      return { success: false, error: msg };
    } finally {
      setIsStaking(false);
    }
  }, [account, refresh]);

  const unstakeShares = useCallback(async (
    amount: number,
  ): Promise<{ success: boolean; txHash?: string; error?: string }> => {
    if (!account) return { success: false, error: 'Wallet not connected' };
    setIsUnstaking(true);
    try {
      const [low, high] = u256Calldata(toWei(amount));
      const tx = await account.execute([{
        contractAddress: CONTRACTS.STAKER,
        entrypoint: 'unstake',
        calldata: [low, high],
      }]);
      setTimeout(refresh, 4000);
      return { success: true, txHash: tx.transaction_hash };
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error('[useVaultManager] unstakeShares error:', msg);
      return { success: false, error: msg };
    } finally {
      setIsUnstaking(false);
    }
  }, [account, refresh]);

  const claimRewards = useCallback(async (): Promise<{ success: boolean; txHash?: string; error?: string }> => {
    if (!account) return { success: false, error: 'Wallet not connected' };
    setIsClaimingRewards(true);
    try {
      const tx = await account.execute([{
        contractAddress: CONTRACTS.STAKER,
        entrypoint: 'claim_rewards',
        calldata: [],
      }]);
      setTimeout(refresh, 4000);
      return { success: true, txHash: tx.transaction_hash };
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error('[useVaultManager] claimRewards error:', msg);
      return { success: false, error: msg };
    } finally {
      setIsClaimingRewards(false);
    }
  }, [account, refresh]);

  return {
    // ── existing ──────────────────────────────────────────────────────────
    wbtcBalance,
    userDepositBTC,
    userShares,
    stats,
    isLoading,
    isDepositing,
    isWithdrawing,
    isFauceting,
    isRebalancing,
    deposit,
    withdraw,
    faucet,
    rebalance,
    refresh,
    // ── new: LEVAMM / VirtualPool / Staker ──────────────────────────────
    levammStats,
    stakerStats,
    isSwapping,
    isVirtualRebalancing,
    isStaking,
    isUnstaking,
    isClaimingRewards,
    levammSwap,
    virtualRebalance,
    stakeShares,
    unstakeShares,
    claimRewards,
  };
}
