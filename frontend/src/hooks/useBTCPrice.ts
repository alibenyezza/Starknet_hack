import { useState, useEffect, useCallback } from 'react';
import { APP_CONFIG } from '@/config/constants';

export function useBTCPrice() {
  const [price, setPrice] = useState(0);
  const [priceChange24h, setPriceChange24h] = useState(0);
  const [isLoading, setIsLoading] = useState(false);

  const fetchPrice = useCallback(async () => {
    try {
      setIsLoading(true);
      const res = await fetch(
        'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd&include_24hr_change=true',
        { cache: 'no-store' }
      );
      if (!res.ok) throw new Error('Network response not ok');
      const data = await res.json();
      setPrice(Math.round(data.bitcoin.usd));
      setPriceChange24h(parseFloat(data.bitcoin.usd_24h_change.toFixed(2)));
    } catch {
      // Keep previous price on error; no console spam
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchPrice();
    const interval = setInterval(fetchPrice, APP_CONFIG.REFRESH_INTERVAL);
    return () => clearInterval(interval);
  }, [fetchPrice]);

  return {
    price,
    priceChange24h,
    isLoading,
    refresh: fetchPrice,
  };
}
