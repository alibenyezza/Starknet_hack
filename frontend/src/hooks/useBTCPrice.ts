import { useState, useEffect, useCallback } from 'react';

// Binance public API — CORS-friendly, no API key, no rate limit for these endpoints
const BINANCE_24H = 'https://api.binance.com/api/v3/ticker/24hr?symbol=BTCUSDT';
const REFRESH_MS = 30_000; // 30 s — Binance is fine with this

export function useBTCPrice() {
  const [price, setPrice] = useState(0);
  const [priceChange24h, setPriceChange24h] = useState(0);
  const [isLoading, setIsLoading] = useState(false);

  const fetchPrice = useCallback(async () => {
    try {
      setIsLoading(true);
      const res = await fetch(BINANCE_24H);
      if (!res.ok) throw new Error(`Binance ${res.status}`);
      const data = await res.json();
      setPrice(Math.round(parseFloat(data.lastPrice)));
      setPriceChange24h(parseFloat(parseFloat(data.priceChangePercent).toFixed(2)));
    } catch {
      // Keep previous value silently
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchPrice();
    const id = setInterval(fetchPrice, REFRESH_MS);
    return () => clearInterval(id);
  }, [fetchPrice]);

  return { price, priceChange24h, isLoading, refresh: fetchPrice };
}
