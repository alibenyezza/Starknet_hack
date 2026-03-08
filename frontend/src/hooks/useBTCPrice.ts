import { useState, useEffect, useCallback, useMemo } from 'react';
import { RpcProvider, Contract, uint256 } from 'starknet';
import { CONTRACTS } from '@/config/constants';

// Binance public API — CORS-friendly, no API key, no rate limit for these endpoints
const BINANCE_24H = 'https://api.binance.com/api/v3/ticker/24hr?symbol=BTCUSDT';
const REFRESH_MS = 30_000; // 30 s — Binance is fine with this

// Minimal ABI for MockEkuboAdapter.get_btc_price() — on-chain fallback
const EKUBO_PRICE_ABI = [
  { type: 'function', name: 'get_btc_price', inputs: [], outputs: [{ type: 'core::integer::u256' }], state_mutability: 'view' },
] as const;

/** Safely convert starknet.js u256 return value to bigint */
function toBigInt(val: unknown): bigint {
  if (val === undefined || val === null) return 0n;
  if (typeof val === 'bigint') return val;
  if (typeof val === 'number') return BigInt(Math.floor(val));
  if (typeof val === 'string') return BigInt(val);
  if (typeof val === 'object' && 'low' in (val as object) && 'high' in (val as object)) {
    const u = val as { low: bigint; high: bigint };
    return uint256.uint256ToBN({ low: u.low, high: u.high });
  }
  return 0n;
}

export function useBTCPrice() {
  const [price, setPrice] = useState(0);
  const [priceChange24h, setPriceChange24h] = useState(0);
  const [isLoading, setIsLoading] = useState(false);

  // On-chain fallback: read BTC price from MockEkuboAdapter
  const rpc = useMemo(() => new RpcProvider({ nodeUrl: '/rpc', blockIdentifier: 'latest' }), []);
  const ekuboContract = useMemo(
    () => new Contract(EKUBO_PRICE_ABI as any, CONTRACTS.MOCK_EKUBO_ADAPTER, rpc),
    [rpc],
  );

  const fetchPrice = useCallback(async () => {
    try {
      setIsLoading(true);
      const res = await fetch(BINANCE_24H);
      if (!res.ok) throw new Error(`Binance ${res.status}`);
      const data = await res.json();
      setPrice(Math.round(parseFloat(data.lastPrice)));
      setPriceChange24h(parseFloat(parseFloat(data.priceChangePercent).toFixed(2)));
    } catch {
      // Binance failed — fall back to on-chain MockEkubo price
      try {
        const raw = await ekuboContract.get_btc_price();
        const onChainPrice = Number(toBigInt(raw)); // raw integer e.g. 96000
        if (onChainPrice > 0) {
          setPrice(onChainPrice);
          // priceChange24h is unavailable on-chain — keep previous value
        }
        console.warn('[useBTCPrice] Binance unavailable, using on-chain fallback:', onChainPrice);
      } catch (onChainErr) {
        console.error('[useBTCPrice] Both Binance and on-chain fallback failed:', onChainErr);
        // Keep previous value silently
      }
    } finally {
      setIsLoading(false);
    }
  }, [ekuboContract]);

  useEffect(() => {
    fetchPrice();
    const id = setInterval(fetchPrice, REFRESH_MS);
    return () => clearInterval(id);
  }, [fetchPrice]);

  return { price, priceChange24h, isLoading, refresh: fetchPrice };
}
