import { useState, useEffect, useCallback } from 'react';

const COINGECKO_URL =
  'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd&include_24hr_change=true';

export function useBTCPrice() {
  const [price, setPrice] = useState(97000);
  const [priceChange24h, setPriceChange24h] = useState(0);
  const [isLoading, setIsLoading] = useState(false);

  const fetchPrice = useCallback(async () => {
    try {
      setIsLoading(true);
      const res = await fetch(COINGECKO_URL);
      if (!res.ok) throw new Error('Network response not ok');
      const data = await res.json();
      setPrice(Math.round(data.bitcoin.usd));
      setPriceChange24h(parseFloat(data.bitcoin.usd_24h_change.toFixed(2)));
    } catch {
      // CoinGecko may block browser CORS — keep fallback price silently
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchPrice();
    // Refresh every 60s instead of 15s to avoid rate limits
    const interval = setInterval(fetchPrice, 60000);
    return () => clearInterval(interval);
  }, [fetchPrice]);

  return {
    price,
    priceChange24h,
    isLoading,
    refresh: fetchPrice,
  };
}
