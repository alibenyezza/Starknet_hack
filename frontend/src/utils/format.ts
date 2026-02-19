import { DECIMALS, FORMAT } from '@/config/constants';

export function formatBTC(value: number | bigint, includeSymbol = true): string {
  const num = typeof value === 'bigint' ? Number(value) / 10 ** DECIMALS.BTC : value;
  const formatted = new Intl.NumberFormat('en-US', FORMAT.BTC).format(num);
  return includeSymbol ? `${formatted} BTC` : formatted;
}

export function formatUSD(value: number, includeSymbol = true): string {
  const formatted = new Intl.NumberFormat('en-US', FORMAT.USD).format(value);
  return includeSymbol ? `$${formatted}` : formatted;
}

export function formatPercent(value: number, includeSymbol = true): string {
  const formatted = new Intl.NumberFormat('en-US', FORMAT.PERCENT).format(value);
  return includeSymbol ? `${formatted}%` : formatted;
}

export function formatNumber(value: number, decimals = 2): string {
  return new Intl.NumberFormat('en-US', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(value);
}

export function formatAddress(address: string, chars = 6): string {
  if (!address) return '';
  return `${address.substring(0, chars + 2)}...${address.substring(address.length - chars)}`;
}

export function formatRelativeTime(timestamp: number): string {
  const now = Date.now();
  const diff = now - timestamp;

  const seconds = Math.floor(diff / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);

  if (days > 0) return `${days}d ago`;
  if (hours > 0) return `${hours}h ago`;
  if (minutes > 0) return `${minutes}m ago`;
  return 'Just now';
}

export function parseBTCInput(input: string): bigint {
  const num = parseFloat(input);
  if (isNaN(num)) return 0n;
  return BigInt(Math.floor(num * 10 ** DECIMALS.BTC));
}

export function formatBTCFromBigInt(value: bigint): number {
  return Number(value) / 10 ** DECIMALS.BTC;
}
