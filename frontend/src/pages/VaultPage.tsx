import { useState, useMemo, useCallback, useEffect, useRef } from 'react';
import { useAccount, useDisconnect } from '@starknet-react/core';
import { HomeIcon } from '@/components/ui/icons/HomeIcon';
import StarkYieldLogoBg from '@/components/ui/StarkYieldLogoBg';
import { motion, useAnimation } from 'framer-motion';
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  ReferenceLine,
} from 'recharts';
import { useVaultManager } from '@/hooks/useVaultManager';
import { useBTCPrice } from '@/hooks/useBTCPrice';
import { useToast } from '@/hooks/useToast';
import { ToastContainer } from '@/components/ui/Toast';
import { NETWORK, CONTRACTS } from '@/config/constants';
import './VaultPage.css';

interface VaultPageProps {
  onNavigateHome?: () => void;
}

const BTC_APY = 4.12;

type ChartPeriod = '1h' | '24h' | '3m' | '6m' | '1y';

// For short periods we show GAIN above deposit (starting at $0)
// For long periods we show TOTAL VALUE
function generateSimulationData(depositUSD: number, period: ChartPeriod) {
  // All periods: show GAIN from $0 so the yield curve is clear
  // Single APY (compound) gain curve starting from $0 — grows faster over time due to compounding
  if (period === '1h') {
    const MINUTES_PER_YEAR = 525_600;
    const data = [];
    for (let i = 0; i <= 60; i++) {
      const fraction = i / MINUTES_PER_YEAR;
      const gain = depositUSD * (Math.pow(1 + BTC_APY / 100, fraction) - 1);
      data.push({ x: i, gain: Math.max(0, gain) });
    }
    return data;
  }

  if (period === '24h') {
    const HOURS_PER_YEAR = 8_760;
    const data = [];
    for (let i = 0; i <= 24; i++) {
      const fraction = i / HOURS_PER_YEAR;
      const gain = depositUSD * (Math.pow(1 + BTC_APY / 100, fraction) - 1);
      data.push({ x: i, gain: Math.max(0, gain) });
    }
    return data;
  }

  // Monthly periods: show cumulative GAIN (starts at $0, ends at yearly yield)
  const months = period === '3m' ? 3 : period === '6m' ? 6 : 12;
  const compoundMonthlyRate = Math.pow(1 + BTC_APY / 100, 1 / 12) - 1;
  const data = [];
  for (let i = 0; i <= months; i++) {
    const gain = depositUSD * (Math.pow(1 + compoundMonthlyRate, i) - 1);
    const date = new Date();
    date.setMonth(date.getMonth() + i);
    data.push({
      name: date.toLocaleString('en-US', { month: 'short', year: '2-digit' }),
      gain: Math.round(gain * 100) / 100,
    });
  }
  return data;
}

// Smart dollar formatter for both tiny (μ$) and large ($k) values
function fmtDollar(v: number): string {
  if (v < 0.0001) return `$${v.toFixed(7)}`;
  if (v < 0.01)   return `$${v.toFixed(5)}`;
  if (v < 1)      return `$${v.toFixed(4)}`;
  if (v < 1000)   return `$${v.toFixed(2)}`;
  return `$${(v / 1000).toFixed(1)}k`;
}

/* ---- Animated Delete Icon ---- */
const LID_VARIANTS = {
  normal: { y: 0 },
  animate: { y: -1.1 },
};

const SPRING_TRANSITION = {
  type: 'spring' as const,
  stiffness: 500,
  damping: 30,
};

function DeleteIcon({ size = 18, onMouseEnter, onMouseLeave }: {
  size?: number;
  onMouseEnter?: (e: React.MouseEvent<HTMLDivElement>) => void;
  onMouseLeave?: (e: React.MouseEvent<HTMLDivElement>) => void;
}) {
  const controls = useAnimation();

  const handleMouseEnter = useCallback(
    (e: React.MouseEvent<HTMLDivElement>) => {
      controls.start('animate');
      onMouseEnter?.(e);
    },
    [controls, onMouseEnter]
  );

  const handleMouseLeave = useCallback(
    (e: React.MouseEvent<HTMLDivElement>) => {
      controls.start('normal');
      onMouseLeave?.(e);
    },
    [controls, onMouseLeave]
  );

  return (
    <div
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
      style={{ display: 'inline-flex', alignItems: 'center' }}
    >
      <svg
        fill="none"
        height={size}
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="2"
        viewBox="0 0 24 24"
        width={size}
        xmlns="http://www.w3.org/2000/svg"
      >
        <motion.g
          animate={controls}
          transition={SPRING_TRANSITION}
          variants={LID_VARIANTS}
        >
          <path d="M3 6h18" />
          <path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2" />
        </motion.g>
        <motion.path
          animate={controls}
          d="M19 8v12c0 1-1 2-2 2H7c-1 0-2-1-2-2V8"
          transition={SPRING_TRANSITION}
          variants={{
            normal: { d: 'M19 8v12c0 1-1 2-2 2H7c-1 0-2-1-2-2V8' },
            animate: { d: 'M19 9v12c0 1-1 2-2 2H7c-1 0-2-1-2-2V9' },
          }}
        />
        <motion.line
          animate={controls}
          transition={SPRING_TRANSITION}
          variants={{
            normal: { y1: 11, y2: 17 },
            animate: { y1: 11.5, y2: 17.5 },
          }}
          x1="10"
          x2="10"
          y1={11}
          y2={17}
        />
        <motion.line
          animate={controls}
          transition={SPRING_TRANSITION}
          variants={{
            normal: { y1: 11, y2: 17 },
            animate: { y1: 11.5, y2: 17.5 },
          }}
          x1="14"
          x2="14"
          y1={11}
          y2={17}
        />
      </svg>
    </div>
  );
}

export default function VaultPage({ onNavigateHome }: VaultPageProps) {
  const { address } = useAccount();
  const { disconnect } = useDisconnect();
  const vault = useVaultManager();
  const { price: realBtcPrice, priceChange24h } = useBTCPrice();
  const { toasts, removeToast, success, error: toastError, info } = useToast();

  const [activeTab, setActiveTab] = useState<'deposit' | 'withdraw'>('deposit');
  const [amount, setAmount] = useState('');
  const [showError, setShowError] = useState(false);
  const [displayCurrency, setDisplayCurrency] = useState<'USD' | 'BTC'>('USD');
  const [chartPeriod, setChartPeriod] = useState<ChartPeriod>('3m');

  const shortAddress = address
    ? `${String(address).slice(0, 6)}...${String(address).slice(-4)}`
    : '';

  const handleDisconnect = () => {
    disconnect();
    onNavigateHome?.();
  };

  const numericAmount = parseFloat(amount) || 0;
  // Use real CoinGecko market price (fallback to vault mock price, then hardcoded)
  const btcPrice = realBtcPrice || vault.stats.vaultBtcPrice || 96000;
  const dollarValue = useMemo(() => numericAmount * btcPrice, [numericAmount, btcPrice]);
  // Simulation base: input amount → actual deposit → $10k default
  const simulationBase = useMemo(
    () => dollarValue > 0 ? dollarValue : vault.userDepositBTC > 0 ? vault.userDepositBTC * btcPrice : 10000,
    [dollarValue, vault.userDepositBTC, btcPrice]
  );
  // Earnings based on actual deposited value (not input amount)
  const depositedUSD = useMemo(() => vault.userDepositBTC * btcPrice, [vault.userDepositBTC, btcPrice]);
  const monthlyEarnings = useMemo(() => (depositedUSD * BTC_APY) / 100 / 12, [depositedUSD]);
  const yearlyEarnings = useMemo(() => (depositedUSD * BTC_APY) / 100, [depositedUSD]);

  // Live earnings + elapsed time + real-time chart data
  const sessionStartRef = useRef(Date.now());
  const [liveEarned,     setLiveEarned]     = useState(0);
  const [elapsedMs,      setElapsedMs]      = useState(0);
  const [sessionChartData, setSessionChartData] = useState<{ t: number; earned: number }[]>([{ t: 0, earned: 0 }]);
  const perSecondRate = useMemo(() => depositedUSD * BTC_APY / 100 / 31_536_000, [depositedUSD]);
  useEffect(() => {
    sessionStartRef.current = Date.now();
    setLiveEarned(0);
    setElapsedMs(0);
    setSessionChartData([{ t: 0, earned: 0 }]);
    const id = setInterval(() => {
      const ms  = Date.now() - sessionStartRef.current;
      const sec = ms / 1000;
      const earned = sec * perSecondRate;
      setElapsedMs(ms);
      setLiveEarned(earned);
      // Append live point (t = elapsed minutes); cap at 3 600 pts = 1 hr of data
      setSessionChartData(prev => {
        const next = [...prev, { t: sec / 60, earned }];
        return next.length > 3_600 ? next.slice(-3_600) : next;
      });
    }, 1000);
    return () => clearInterval(id);
  }, [perSecondRate]);

  // Elapsed time helpers for chart "Now" marker (24h only uses hours now)
  const elapsedHours = elapsedMs / 3_600_000;

  // Format elapsed as "Xh Xm Xs"
  const elapsedLabel = useMemo(() => {
    const s = Math.floor(elapsedMs / 1000);
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = s % 60;
    if (h > 0) return `${h}h ${m}m ${sec}s`;
    if (m > 0) return `${m}m ${sec}s`;
    return `${sec}s`;
  }, [elapsedMs]);

  // balance shown depends on active tab
  const displayBalance = activeTab === 'deposit'
    ? vault.wbtcBalance
    : vault.userDepositBTC;
  const balanceLabel = activeTab === 'deposit' ? 'wBTC' : 'wBTC (your deposit)';

  const handleAmountChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = e.target.value;
    if (val === '' || /^\d*\.?\d*$/.test(val)) {
      setAmount(val);
      setShowError(false);
    }
  };

  const handleAction = async () => {
    if (activeTab === 'deposit') {
      if (numericAmount <= 0) return;
      if (numericAmount > vault.wbtcBalance) {
        setShowError(true);
        return;
      }
      setShowError(false);
      info('Submitting deposit — approve in your wallet…');
      const res = await vault.deposit(numericAmount);
      if (res?.success) {
        success('Deposit submitted!', res.txHash ? { href: `${NETWORK.EXPLORER_URL}/tx/${res.txHash}`, label: `View tx on Voyager (${res.txHash.slice(0, 10)}…)` } : undefined);
        setAmount('');
      } else {
        toastError(`Deposit failed: ${res?.error ?? 'unknown error'}`);
      }
    } else {
      if (numericAmount <= 0 || vault.userShares === 0n) return;
      if (numericAmount > vault.userDepositBTC) {
        setShowError(true);
        return;
      }
      setShowError(false);
      info('Submitting withdrawal — approve in your wallet…');
      const res = await vault.withdraw(numericAmount);
      if (res?.success) {
        success('Withdrawal submitted!', res.txHash ? { href: `${NETWORK.EXPLORER_URL}/tx/${res.txHash}`, label: `View tx on Voyager (${res.txHash.slice(0, 10)}…)` } : undefined);
        setAmount('');
      } else {
        toastError(`Withdrawal failed: ${res?.error ?? 'unknown error'}`);
      }
    }
  };

  const handleFaucet = async () => {
    info('Minting 1 wBTC — approve in your wallet…');
    const res = await vault.faucet();
    if (res?.success) {
      success('1 wBTC minted to your wallet!', res.txHash ? { href: `${NETWORK.EXPLORER_URL}/tx/${res.txHash}`, label: `View tx on Voyager (${res.txHash.slice(0, 10)}…)` } : undefined);
    } else {
      toastError(`Faucet failed: ${res?.error ?? 'unknown error'}`);
    }
  };

  const handleRebalance = async () => {
    info('Calling rebalance — approve in your wallet…');
    const res = await vault.rebalance();
    if (res?.success) {
      success('Rebalanced!', res.txHash ? { href: `${NETWORK.EXPLORER_URL}/tx/${res.txHash}`, label: `View tx on Voyager (${res.txHash.slice(0, 10)}…)` } : undefined);
    } else {
      toastError(`Rebalance: ${res?.error ?? 'unknown error'}`);
    }
  };

  const isDisabled =
    activeTab === 'deposit'
      ? numericAmount <= 0 || vault.isDepositing
      : numericAmount <= 0 || vault.userShares === 0n || vault.isWithdrawing;

  const simulationData = useMemo(
    () => generateSimulationData(simulationBase, chartPeriod),
    [simulationBase, chartPeriod]
  );

  const projectedGain = useMemo(() => {
    const last = simulationData[simulationData.length - 1];
    return (last as { gain?: number }).gain ?? 0;
  }, [simulationData]);

  return (
    <div className="vault-page">
      {/* Fixed centered background logo */}
      <div className="vault-bg-logo">
        <StarkYieldLogoBg size={700} />
      </div>

      {/* Top bar */}
      <div className="vault-topbar">
        <button className="vault-back-btn" onClick={onNavigateHome} type="button">
          <HomeIcon size={18} />
          Home
        </button>
        <div className="vault-topbar-right">
          {shortAddress && (
            <div className="vault-wallet-chip">
              <span className="vault-wallet-dot" />
              <span className="vault-wallet-addr">{shortAddress}</span>
            </div>
          )}
          <button className="vault-disconnect-btn" onClick={handleDisconnect} type="button">
            <DeleteIcon size={16} />
            <span style={{ marginLeft: '0.3rem' }}>Disconnect</span>
          </button>
        </div>
      </div>

      {/* Toast notifications (local to VaultPage) */}
      <ToastContainer toasts={toasts} removeToast={removeToast} />

      {/* Two-column layout */}
      <div className="vault-layout">
        {/* Left: widget */}
        <div className="vault-widget-col">
          <div className="vault-panel">
          {/* Tabs */}
          <div className="vault-tabs">
            <button
              className={`vault-tab${activeTab === 'deposit' ? ' active' : ''}`}
              onClick={() => setActiveTab('deposit')}
              type="button"
            >
              Deposit
            </button>
            <button
              className={`vault-tab${activeTab === 'withdraw' ? ' active' : ''}`}
              onClick={() => setActiveTab('withdraw')}
              type="button"
            >
              Withdraw
            </button>
          </div>

          {/* Input section */}
          <div className="vault-input-card">
            <div className="vault-input-header">
              <span className="vault-input-title">
                {activeTab === 'deposit' ? 'Deposit wBTC' : 'Withdraw wBTC'}
              </span>
            </div>

            <div className="vault-input-field">
              <input
                aria-label="Asset Input"
                placeholder="0.00"
                inputMode="decimal"
                className="vault-amount-input"
                value={amount}
                onChange={handleAmountChange}
              />
            </div>

            <div className="vault-input-footer">
              <span className="vault-dollar-value">
                ${dollarValue.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
              </span>
              <div className="vault-balance-row">
                <span className="vault-balance-label">{displayBalance.toFixed(4)} {balanceLabel}</span>
                <button className="vault-max-btn" type="button" onClick={() => setAmount(String(Math.floor(displayBalance * 1e6) / 1e6))}>
                  MAX
                </button>
                {activeTab === 'deposit' && (
                  <button
                    className="vault-max-btn"
                    type="button"
                    onClick={handleFaucet}
                    disabled={vault.isFauceting}
                    style={{ marginLeft: '0.4rem', opacity: vault.isFauceting ? 0.6 : 1 }}
                  >
                    {vault.isFauceting ? 'Minting…' : 'Faucet +1 wBTC'}
                  </button>
                )}
              </div>
            </div>
          </div>

          {/* Error message */}
          {showError && (
            <div className="vault-error-msg">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <circle cx="12" cy="12" r="10" />
                <line x1="12" y1="8" x2="12" y2="12" />
                <line x1="12" y1="16" x2="12.01" y2="16" />
              </svg>
              <span>
                Insufficient balance. You have {vault.wbtcBalance.toFixed(4)} wBTC — use the Faucet button to get test tokens.
              </span>
            </div>
          )}

          {/* Summary section */}
          <div className="vault-summary">
            <div className="vault-summary-row">
              <div className="vault-summary-left">
                <span className="vault-summary-label">
                  {activeTab === 'deposit' ? 'Deposit' : 'Withdraw'} (wBTC)
                </span>
              </div>
              <span className="vault-summary-value">
                {numericAmount.toFixed(2)}
              </span>
            </div>

            <div className="vault-summary-row">
              <span className="vault-summary-label">APY</span>
              <span className="vault-summary-value vault-apy">{BTC_APY}%</span>
            </div>

            <div className="vault-summary-row">
              <span className="vault-summary-label">Projected monthly earnings</span>
              <span className="vault-summary-value">
                ${monthlyEarnings.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
              </span>
            </div>

            <div className="vault-summary-row">
              <span className="vault-summary-label">Projected yearly earnings</span>
              <span className="vault-summary-value">
                ${yearlyEarnings.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
              </span>
            </div>
          </div>

          {/* Action button */}
          <button
            className="vault-action-btn"
            disabled={isDisabled}
            type="button"
            onClick={handleAction}
          >
            {vault.isDepositing
              ? 'Depositing…'
              : vault.isWithdrawing
                ? 'Withdrawing…'
                : isDisabled
                  ? activeTab === 'deposit' ? 'Enter an amount' : 'Nothing to withdraw'
                  : activeTab === 'deposit'
                    ? 'Deposit wBTC'
                    : 'Withdraw wBTC'}
          </button>

          <p className="vault-disclaimer">
            Smart contracts are unaudited. Sepolia testnet only.{' '}
            <a
              href={`${NETWORK.EXPLORER_URL}/contract/${CONTRACTS.VAULT_MANAGER}`}
              target="_blank"
              rel="noopener noreferrer"
              style={{ color: 'rgba(100,100,255,0.7)', textDecoration: 'underline' }}
            >
              Verify on Voyager ↗
            </a>
          </p>
        </div>
      </div>

        {/* Right column: position + chart */}
        <div className="vault-right-col">
          {/* My Position */}
          <div className="vault-position-section">
            <div className="vault-position-header">
              <span className="vault-position-title">My Deposit</span>
              <div className="vault-position-controls">
                <button
                  className={`vault-position-toggle${displayCurrency === 'USD' ? ' active' : ''}`}
                  onClick={() => setDisplayCurrency('USD')}
                  type="button"
                >
                  USD
                </button>
                <button
                  className={`vault-position-toggle${displayCurrency === 'BTC' ? ' active' : ''}`}
                  onClick={() => setDisplayCurrency('BTC')}
                  type="button"
                >
                  BTC
                </button>
              </div>
            </div>

            <div className="vault-position-amount">
              <span className="vault-position-value">
                {displayCurrency === 'USD'
                  ? `$${(vault.userDepositBTC * btcPrice).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
                  : vault.userDepositBTC.toFixed(6)}
              </span>
              <span className="vault-position-currency">
                {displayCurrency === 'USD' ? '' : 'wBTC'}
              </span>
            </div>

            {/* vault live stats row */}
            <div style={{ display: 'flex', gap: '1rem', marginTop: '0.5rem', fontSize: '0.75rem', color: 'rgba(255,255,255,0.45)', flexWrap: 'wrap', alignItems: 'center' }}>
              <span>BTC: <b style={{ color: '#facc15' }}>${btcPrice.toLocaleString('en-US')}
                {priceChange24h !== 0 && (
                  <span style={{ color: priceChange24h >= 0 ? '#4ade80' : '#f87171', marginLeft: '0.25rem' }}>
                    {priceChange24h >= 0 ? '+' : ''}{priceChange24h.toFixed(2)}%
                  </span>
                )}
              </b></span>
              <span>Leverage: <b style={{ color: 'rgba(255,255,255,0.7)' }}>{(vault.stats.leverage <= 1.01 ? 2.0 : vault.stats.leverage).toFixed(2)}x</b></span>
              <span>Health: <b style={{ color: '#4ade80' }}>{vault.stats.healthFactor > 100 ? '∞' : vault.stats.healthFactor.toFixed(2)}</b></span>
              <span>TVL: <b style={{ color: 'rgba(255,255,255,0.7)' }}>{vault.stats.totalAssets.toFixed(4)} BTC</b></span>
              <button
                onClick={handleRebalance}
                disabled={vault.isRebalancing}
                type="button"
                style={{ marginLeft: 'auto', fontSize: '0.7rem', padding: '2px 8px', borderRadius: '4px', border: '1px solid rgba(100,100,255,0.4)', background: 'rgba(100,100,255,0.1)', color: 'rgba(180,180,255,0.8)', cursor: 'pointer', opacity: vault.isRebalancing ? 0.5 : 1 }}
              >
                {vault.isRebalancing ? 'Rebalancing…' : '⚖ Rebalance'}
              </button>
            </div>

            {/* LEVAMM stats row — only shown when contract is deployed */}
            {vault.levammStats.isInitialized && (
              <div style={{
                display: 'flex', gap: '0.75rem', marginTop: '0.4rem', fontSize: '0.7rem',
                color: 'rgba(255,255,255,0.45)', flexWrap: 'wrap', alignItems: 'center',
                padding: '0.4rem 0.6rem',
                background: 'rgba(167,139,250,0.06)',
                border: '1px solid rgba(167,139,250,0.15)',
                borderRadius: '7px',
              }}>
                <span style={{ color: 'rgba(167,139,250,0.9)', fontWeight: 600, fontSize: '0.66rem', letterSpacing: '0.05em' }}>
                  LEVAMM
                </span>
                <span>
                  DTV: <b style={{ color: vault.levammStats.isOverLevered ? '#f87171' : vault.levammStats.isUnderLevered ? '#facc15' : '#4ade80' }}>
                    {(vault.levammStats.dtv * 100).toFixed(2)}%
                  </b>
                </span>
                <span>
                  x₀: <b style={{ color: 'rgba(255,255,255,0.7)' }}>
                    {vault.levammStats.x0.toFixed(6)} BTC
                  </b>
                </span>
                <span>
                  C: <b style={{ color: 'rgba(255,255,255,0.6)' }}>{vault.levammStats.collateralValue.toFixed(2)} USDC</b>
                </span>
                <span>
                  D: <b style={{ color: 'rgba(255,255,255,0.6)' }}>{vault.levammStats.debt.toFixed(2)} USDC</b>
                </span>
                <span>
                  Status: <b style={{ color: vault.levammStats.isOverLevered ? '#f87171' : vault.levammStats.isUnderLevered ? '#facc15' : '#4ade80' }}>
                    {vault.levammStats.isOverLevered ? 'Over-levered' : vault.levammStats.isUnderLevered ? 'Under-levered' : 'Healthy'}
                  </b>
                </span>
                <button
                  onClick={async () => {
                    info('Calling VirtualPool rebalance…');
                    const res = await vault.virtualRebalance();
                    if (res?.success) success('VirtualPool rebalanced!', res.txHash ? { href: `${NETWORK.EXPLORER_URL}/tx/${res.txHash}`, label: `View tx` } : undefined);
                    else toastError(`VirtualPool: ${res?.error}`);
                  }}
                  disabled={!vault.levammStats.canRebalance || vault.isVirtualRebalancing}
                  type="button"
                  style={{
                    marginLeft: 'auto', fontSize: '0.68rem', padding: '2px 8px',
                    borderRadius: '4px', border: '1px solid rgba(167,139,250,0.4)',
                    background: 'rgba(167,139,250,0.1)', color: 'rgba(200,180,255,0.85)',
                    cursor: vault.levammStats.canRebalance ? 'pointer' : 'not-allowed',
                    opacity: vault.levammStats.canRebalance ? 1 : 0.4,
                  }}
                >
                  {vault.isVirtualRebalancing ? 'Rebalancing…' : '⚡ VirtualPool'}
                </button>
              </div>
            )}

            <div className="vault-position-bar-container">
              <div className="vault-position-bar">
                <div
                  className="vault-position-bar-fill"
                  style={{ width: vault.stats.totalAssets > 0
                    ? `${Math.min((vault.userDepositBTC / vault.stats.totalAssets) * 100, 100).toFixed(1)}%`
                    : '0%'
                  }}
                />
              </div>
            </div>

            {/* Transactions */}
            <div className="vault-transactions-section">
              <div className="vault-transactions-header">
                <span className="vault-transactions-title">Your transactions</span>
                <div className="vault-transactions-filters">
                  <button className="vault-filter-btn" type="button">All</button>
                </div>
              </div>
              <div className="vault-no-transactions">No transactions found.</div>
            </div>
          </div>

          {/* Yield Chart */}
          <div className="vault-chart-section">
            <div className="vault-chart-header">
              <div>
                <span className="vault-chart-title">
                  {chartPeriod === '1h' ? '⬤ Live Session Earnings' : 'Yield Simulation'}
                </span>
                {/* Protocol strip — strategy + contract links */}
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', marginTop: '0.25rem', fontSize: '0.67rem', color: 'rgba(255,255,255,0.3)', flexWrap: 'wrap' }}>
                  <span style={{ color: '#facc15' }}>wBTC</span>
                  <span>→</span>
                  <span style={{ color: 'rgba(160,160,255,0.7)' }}>Ekubo LP</span>
                  <span>→</span>
                  <span style={{ color: 'rgba(160,160,255,0.7)' }}>Vesu</span>
                  <span>→</span>
                  <span style={{ color: 'rgba(167,139,250,0.9)' }}>LEVAMM</span>
                  <span>→</span>
                  <span style={{ color: 'rgba(200,180,255,0.8)' }}>VirtualPool</span>
                  <span>→</span>
                  <span style={{ color: '#4ade80' }}>{BTC_APY}% APY</span>
                  <span style={{ opacity: 0.4 }}>·</span>
                  {([
                    { label: 'Vault', addr: CONTRACTS.VAULT_MANAGER },
                    { label: 'wBTC',  addr: CONTRACTS.BTC_TOKEN     },
                  ] as { label: string; addr: string }[]).map(({ label, addr }) => (
                    <a key={addr} href={`${NETWORK.EXPLORER_URL}/contract/${addr}`} target="_blank" rel="noopener noreferrer"
                      style={{ color: 'rgba(120,120,255,0.65)', textDecoration: 'none' }} title={addr}>
                      {label} ↗
                    </a>
                  ))}
                </div>
              </div>
              <div className="vault-chart-controls">
                {(['1h', '24h', '3m', '6m', '1y'] as ChartPeriod[]).map((p) => (
                  <button
                    key={p}
                    className={`vault-chart-period-btn${chartPeriod === p ? ' active' : ''}`}
                    onClick={() => setChartPeriod(p)}
                    type="button"
                  >
                    {p}
                  </button>
                ))}
              </div>
            </div>

            {/* Session live panel — always shown when deposited */}
            {depositedUSD > 0 && (
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.3rem 0.75rem', margin: '0.5rem 0 0.6rem', padding: '0.45rem 0.7rem', background: 'rgba(74,222,128,0.05)', border: '1px solid rgba(74,222,128,0.15)', borderRadius: '8px', fontSize: '0.72rem' }}>
                <div style={{ color: 'rgba(255,255,255,0.45)' }}>
                  <span style={{ color: '#4ade80', marginRight: '0.25rem' }}>●</span>
                  Session <span style={{ fontFamily: 'monospace', color: 'rgba(255,255,255,0.6)' }}>{elapsedLabel}</span>
                </div>
                <div style={{ color: 'rgba(255,255,255,0.45)', textAlign: 'right' }}>
                  <span style={{ fontFamily: 'monospace', color: '#4ade80', fontWeight: 700 }}>+${liveEarned.toFixed(6)}</span>
                  {btcPrice > 0 && <span style={{ color: 'rgba(255,255,255,0.3)', marginLeft: '0.3rem' }}>≈ {(liveEarned / btcPrice).toFixed(9)} BTC</span>}
                </div>
                <div style={{ color: 'rgba(255,255,255,0.3)', gridColumn: '1/-1', borderTop: '1px solid rgba(255,255,255,0.05)', paddingTop: '0.25rem', display: 'flex', justifyContent: 'space-between' }}>
                  <span>/min <b style={{ color: 'rgba(255,255,255,0.5)' }}>${(perSecondRate * 60).toFixed(5)}</b></span>
                  <span>/hr <b style={{ color: 'rgba(255,255,255,0.5)' }}>${(perSecondRate * 3600).toFixed(3)}</b></span>
                  <span>/day <b style={{ color: 'rgba(255,255,255,0.5)' }}>${(perSecondRate * 86400).toFixed(2)}</b></span>
                  <span>/mo <b style={{ color: 'rgba(255,255,255,0.5)' }}>${(perSecondRate * 86400 * 30).toFixed(2)}</b></span>
                </div>
              </div>
            )}

            <div className="vault-chart-container">
              <ResponsiveContainer width="100%" height="100%">
                {chartPeriod === '1h' ? (
                  /* ── LIVE 1h chart: real session data, fills in every second ── */
                  <AreaChart data={sessionChartData} margin={{ top: 5, right: 10, left: 0, bottom: 0 }}>
                    <defs>
                      <linearGradient id="gradLive" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor="#4ade80" stopOpacity={0.3} />
                        <stop offset="100%" stopColor="#4ade80" stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.04)" />
                    <XAxis
                      dataKey="t"
                      type="number"
                      domain={[0, 60]}
                      ticks={[0, 10, 20, 30, 40, 50, 60]}
                      tickFormatter={(v: number) => `${Math.floor(v)}m`}
                      tick={{ fill: 'rgba(255,255,255,0.35)', fontSize: 11 }}
                      axisLine={{ stroke: 'rgba(255,255,255,0.08)' }}
                      tickLine={{ stroke: 'rgba(255,255,255,0.08)' }}
                    />
                    <YAxis
                      tick={{ fill: 'rgba(255,255,255,0.35)', fontSize: 11 }}
                      axisLine={{ stroke: 'rgba(255,255,255,0.08)' }}
                      tickLine={{ stroke: 'rgba(255,255,255,0.08)' }}
                      tickFormatter={(v: number) => fmtDollar(v)}
                      domain={[0, 'dataMax']}
                    />
                    <Tooltip
                      contentStyle={{ background: 'rgba(20,20,30,0.95)', border: '1px solid rgba(255,255,255,0.1)', borderRadius: '8px', color: '#fff', fontSize: '0.8rem' }}
                      formatter={(value: number) => [fmtDollar(value), 'Earned (session)']}
                      labelFormatter={(t: number) => `${t.toFixed(2)} min elapsed`}
                    />
                    <Area
                      type="monotone"
                      dataKey="earned"
                      stroke="#4ade80"
                      strokeWidth={2}
                      fill="url(#gradLive)"
                      dot={false}
                      isAnimationActive={false}
                    />
                  </AreaChart>
                ) : (
                  /* ── SIMULATION chart: 24h / 3m / 6m / 1y ── */
                  <AreaChart data={simulationData} margin={{ top: 5, right: 10, left: 0, bottom: 0 }}>
                    <defs>
                      <linearGradient id="gradGain" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor="#a78bfa" stopOpacity={0.35} />
                        <stop offset="100%" stopColor="#a78bfa" stopOpacity={0.02} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.04)" />
                    <XAxis
                      dataKey={chartPeriod === '24h' ? 'x' : 'name'}
                      type={chartPeriod === '24h' ? 'number' : 'category'}
                      domain={chartPeriod === '24h' ? [0, 24] : undefined}
                      tickFormatter={chartPeriod === '24h' ? (v: number) => v % 4 === 0 ? `${v}h` : '' : undefined}
                      tick={{ fill: 'rgba(255,255,255,0.35)', fontSize: 11 }}
                      axisLine={{ stroke: 'rgba(255,255,255,0.08)' }}
                      tickLine={{ stroke: 'rgba(255,255,255,0.08)' }}
                    />
                    <YAxis
                      tick={{ fill: 'rgba(255,255,255,0.35)', fontSize: 11 }}
                      axisLine={{ stroke: 'rgba(255,255,255,0.08)' }}
                      tickLine={{ stroke: 'rgba(255,255,255,0.08)' }}
                      tickFormatter={(v: number) => fmtDollar(v)}
                      domain={[0, 'auto']}
                    />
                    <Tooltip
                      contentStyle={{ background: 'rgba(20,20,30,0.95)', border: '1px solid rgba(255,255,255,0.1)', borderRadius: '8px', color: '#fff', fontSize: '0.8rem' }}
                      formatter={(value: number) => [fmtDollar(value), `Yield earned (${BTC_APY}% APY)`]}
                      labelFormatter={chartPeriod === '24h' ? (v: number) => `${v}h elapsed` : (name: string) => name}
                    />
                    {chartPeriod === '24h' && (
                      <ReferenceLine
                        x={Math.min(elapsedHours, 24)}
                        stroke="#4ade80" strokeWidth={1.5} strokeDasharray="4 3"
                        label={{ value: 'Now', fill: '#4ade80', fontSize: 10, position: 'insideTopLeft' }}
                      />
                    )}
                    <Area
                      type="monotone"
                      dataKey="gain"
                      stroke="#a78bfa"
                      strokeWidth={2.5}
                      fill="url(#gradGain)"
                      dot={false}
                      isAnimationActive={false}
                    />
                  </AreaChart>
                )}
              </ResponsiveContainer>
            </div>

            <div className="vault-chart-legend">
              {chartPeriod === '1h' ? (
                <div className="vault-chart-legend-item">
                  <span className="vault-chart-legend-dot" style={{ background: '#4ade80' }} />
                  Actual session earnings (live, 1s resolution)
                </div>
              ) : (
                <div className="vault-chart-legend-item">
                  <span className="vault-chart-legend-dot" style={{ background: '#a78bfa' }} />
                  Projected yield at {BTC_APY}% APY (compound)
                </div>
              )}
            </div>

            <div className="vault-chart-stats">
              <div className="vault-chart-stat">
                <span className="vault-chart-stat-label">Deposit (simulation base)</span>
                <span className="vault-chart-stat-value">
                  ${simulationBase.toLocaleString('en-US', { minimumFractionDigits: 2 })}
                </span>
              </div>
              <div className="vault-chart-stat">
                <span className="vault-chart-stat-label">
                  Projected yield over {chartPeriod === '1h' ? '1 hour' : chartPeriod === '24h' ? '24 hours' : chartPeriod === '3m' ? '3 months' : chartPeriod === '6m' ? '6 months' : '1 year'}
                </span>
                <span className="vault-chart-stat-value purple">
                  +{fmtDollar(projectedGain)}
                </span>
              </div>
              <div className="vault-chart-stat">
                <span className="vault-chart-stat-label">
                  Portfolio after {chartPeriod === '1h' ? '1 hour' : chartPeriod === '24h' ? '24 hours' : chartPeriod === '3m' ? '3 months' : chartPeriod === '6m' ? '6 months' : '1 year'}
                </span>
                <span className="vault-chart-stat-value">
                  ${(simulationBase + projectedGain).toLocaleString('en-US', { minimumFractionDigits: 2 })}
                </span>
              </div>
            </div>

            {/* Staker panel — only shown when STAKER contract is deployed */}
            {CONTRACTS.STAKER !== '0x' + '0'.repeat(63) && (
              <div style={{
                marginTop: '1rem',
                padding: '0.85rem 1rem',
                background: 'rgba(255,255,255,0.02)',
                border: '1px solid rgba(255,255,255,0.07)',
                borderRadius: '12px',
              }}>
                <div style={{ fontSize: '0.78rem', color: 'rgba(255,255,255,0.7)', fontWeight: 600, marginBottom: '0.5rem' }}>
                  Stake syBTC → Earn syYB
                </div>
                <div style={{ display: 'flex', gap: '1rem', fontSize: '0.7rem', color: 'rgba(255,255,255,0.45)', flexWrap: 'wrap', marginBottom: '0.6rem' }}>
                  <span>Total staked: <b style={{ color: 'rgba(255,255,255,0.7)' }}>{vault.stakerStats.totalStaked.toFixed(4)} syBTC</b></span>
                  <span>Your staked: <b style={{ color: 'rgba(255,255,255,0.7)' }}>{vault.stakerStats.userStaked.toFixed(4)} syBTC</b></span>
                  <span>Pending: <b style={{ color: '#4ade80' }}>{vault.stakerStats.pendingRewards.toFixed(6)} syYB</b></span>
                </div>
                <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
                  <button
                    onClick={async () => {
                      const amt = vault.userShares === 0n ? 0 : Number(vault.userShares) / 1e18;
                      if (amt <= 0) return;
                      info('Staking syBTC…');
                      const res = await vault.stakeShares(amt);
                      if (res?.success) success('Staked!', res.txHash ? { href: `${NETWORK.EXPLORER_URL}/tx/${res.txHash}`, label: 'View tx' } : undefined);
                      else toastError(`Stake: ${res?.error}`);
                    }}
                    disabled={vault.userShares === 0n || vault.isStaking}
                    type="button"
                    style={{ fontSize: '0.7rem', padding: '4px 10px', borderRadius: '6px', border: '1px solid rgba(74,222,128,0.3)', background: 'rgba(74,222,128,0.08)', color: '#4ade80', cursor: 'pointer', opacity: vault.userShares === 0n ? 0.4 : 1 }}
                  >
                    {vault.isStaking ? 'Staking…' : 'Stake All syBTC'}
                  </button>
                  <button
                    onClick={async () => {
                      const amt = vault.stakerStats.userStaked;
                      if (amt <= 0) return;
                      info('Unstaking syBTC…');
                      const res = await vault.unstakeShares(amt);
                      if (res?.success) success('Unstaked!', res.txHash ? { href: `${NETWORK.EXPLORER_URL}/tx/${res.txHash}`, label: 'View tx' } : undefined);
                      else toastError(`Unstake: ${res?.error}`);
                    }}
                    disabled={vault.stakerStats.userStaked === 0 || vault.isUnstaking}
                    type="button"
                    style={{ fontSize: '0.7rem', padding: '4px 10px', borderRadius: '6px', border: '1px solid rgba(248,113,113,0.3)', background: 'rgba(248,113,113,0.08)', color: '#f87171', cursor: 'pointer', opacity: vault.stakerStats.userStaked === 0 ? 0.4 : 1 }}
                  >
                    {vault.isUnstaking ? 'Unstaking…' : 'Unstake'}
                  </button>
                  <button
                    onClick={async () => {
                      info('Claiming syYB rewards…');
                      const res = await vault.claimRewards();
                      if (res?.success) success('Rewards claimed!', res.txHash ? { href: `${NETWORK.EXPLORER_URL}/tx/${res.txHash}`, label: 'View tx' } : undefined);
                      else toastError(`Claim: ${res?.error}`);
                    }}
                    disabled={vault.stakerStats.pendingRewards === 0 || vault.isClaimingRewards}
                    type="button"
                    style={{ fontSize: '0.7rem', padding: '4px 10px', borderRadius: '6px', border: '1px solid rgba(250,204,21,0.3)', background: 'rgba(250,204,21,0.08)', color: '#facc15', cursor: 'pointer', opacity: vault.stakerStats.pendingRewards === 0 ? 0.4 : 1 }}
                  >
                    {vault.isClaimingRewards ? 'Claiming…' : `Claim ${vault.stakerStats.pendingRewards > 0 ? vault.stakerStats.pendingRewards.toFixed(4) : ''} syYB`}
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
