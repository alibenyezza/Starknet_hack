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

  // /rpc is proxied by Vite to Cartridge — same origin, no CORS
  // blockIdentifier: 'latest' because Cartridge RPC doesn't support 'pending'
  const rpc = useMemo(() => new RpcProvider({ nodeUrl: '/rpc', blockIdentifier: 'latest' }), []);

  // Contract instances
  const btcContract   = useMemo(() => new Contract(ERC20_ABI as any, CONTRACTS.BTC_TOKEN,     rpc), [rpc]);
  const vaultContract = useMemo(() => new Contract(VAULT_ABI as any, CONTRACTS.VAULT_MANAGER, rpc), [rpc]);

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

    setIsLoading(false);
  }, [address, btcContract, vaultContract]);

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
      setTimeout(refresh, 4000); // give the tx a moment to land
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

  return {
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
  };
}
