import { useState, useMemo, useCallback } from 'react';
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
} from 'recharts';
import './VaultPage.css';

interface VaultPageProps {
  onNavigateHome?: () => void;
}

const BTC_APY = 4.12;
const BTC_APR = 4.04;
const USER_BALANCE = 0; // Simulated wallet balance in wBTC

type ChartPeriod = '3m' | '6m' | '1y';

function generateSimulationData(depositUSD: number, period: ChartPeriod) {
  const months = period === '3m' ? 3 : period === '6m' ? 6 : 12;
  const monthlyRate = BTC_APR / 100 / 12;
  const compoundMonthlyRate = Math.pow(1 + BTC_APY / 100, 1 / 12) - 1;
  const data = [];
  for (let i = 0; i <= months; i++) {
    const aprValue = depositUSD * (1 + monthlyRate * i);
    const apyValue = depositUSD * Math.pow(1 + compoundMonthlyRate, i);
    const date = new Date();
    date.setMonth(date.getMonth() + i);
    data.push({
      name: date.toLocaleString('en-US', { month: 'short', year: '2-digit' }),
      apr: Math.round(aprValue * 100) / 100,
      apy: Math.round(apyValue * 100) / 100,
    });
  }
  return data;
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
  const dollarValue = useMemo(() => numericAmount * 97000, [numericAmount]);
  const monthlyEarnings = useMemo(() => (dollarValue * BTC_APY) / 100 / 12, [dollarValue]);
  const yearlyEarnings = useMemo(() => (dollarValue * BTC_APY) / 100, [dollarValue]);

  const handleAmountChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = e.target.value;
    if (val === '' || /^\d*\.?\d*$/.test(val)) {
      setAmount(val);
      setShowError(false);
    }
  };

  const handleAction = () => {
    if (numericAmount > USER_BALANCE) {
      setShowError(true);
      return;
    }
    setShowError(false);
  };

  const isDisabled = numericAmount <= 0;

  const simulationData = useMemo(
    () => generateSimulationData(dollarValue > 0 ? dollarValue : 10000, chartPeriod),
    [dollarValue, chartPeriod]
  );

  const projectedGainAPR = useMemo(() => {
    const last = simulationData[simulationData.length - 1];
    const base = simulationData[0];
    return last.apr - base.apr;
  }, [simulationData]);

  const projectedGainAPY = useMemo(() => {
    const last = simulationData[simulationData.length - 1];
    const base = simulationData[0];
    return last.apy - base.apy;
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
                <span className="vault-balance-label">{USER_BALANCE.toFixed(2)} wBTC</span>
                <button className="vault-max-btn" type="button" onClick={() => setAmount(String(USER_BALANCE))}>
                  MAX
                </button>
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
              <span>Insufficient balance. Your wBTC balance is too low for this transaction.</span>
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
            {isDisabled
              ? 'Enter an amount'
              : activeTab === 'deposit'
                ? 'Deposit wBTC'
                : 'Withdraw wBTC'}
          </button>

          <p className="vault-disclaimer">
            Smart contracts are unaudited. Do not deposit significant mainnet funds.
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
                  ? `$${(0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
                  : (0).toFixed(4)}
              </span>
              <span className="vault-position-currency">
                {displayCurrency === 'USD' ? '' : 'wBTC'}
              </span>
            </div>

            <div className="vault-position-bar-container">
              <div className="vault-position-bar">
                <div className="vault-position-bar-fill" style={{ width: '0%' }} />
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

          {/* Simulation Chart */}
          <div className="vault-chart-section">
            <div className="vault-chart-header">
              <span className="vault-chart-title">Yield Simulation</span>
              <div className="vault-chart-controls">
                {(['3m', '6m', '1y'] as ChartPeriod[]).map((p) => (
                  <button
                    key={p}
                    className={`vault-chart-period-btn${chartPeriod === p ? ' active' : ''}`}
                    onClick={() => setChartPeriod(p)}
                    type="button"
                  >
                    {p === '3m' ? '3 months' : p === '6m' ? '6 months' : '1 year'}
                  </button>
                ))}
              </div>
            </div>

            <div className="vault-chart-container">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={simulationData} margin={{ top: 5, right: 10, left: 0, bottom: 0 }}>
                  <defs>
                    <linearGradient id="gradAPR" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="#4444cc" stopOpacity={0.25} />
                      <stop offset="100%" stopColor="#4444cc" stopOpacity={0} />
                    </linearGradient>
                    <linearGradient id="gradAPY" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="#8888ee" stopOpacity={0.25} />
                      <stop offset="100%" stopColor="#8888ee" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.04)" />
                  <XAxis
                    dataKey="name"
                    tick={{ fill: 'rgba(255,255,255,0.35)', fontSize: 11 }}
                    axisLine={{ stroke: 'rgba(255,255,255,0.08)' }}
                    tickLine={{ stroke: 'rgba(255,255,255,0.08)' }}
                  />
                  <YAxis
                    tick={{ fill: 'rgba(255,255,255,0.35)', fontSize: 11 }}
                    axisLine={{ stroke: 'rgba(255,255,255,0.08)' }}
                    tickLine={{ stroke: 'rgba(255,255,255,0.08)' }}
                    tickFormatter={(v: number) => `$${(v / 1000).toFixed(1)}k`}
                    domain={['dataMin - 100', 'dataMax + 100']}
                  />
                  <Tooltip
                    contentStyle={{
                      background: 'rgba(20, 20, 30, 0.95)',
                      border: '1px solid rgba(255,255,255,0.1)',
                      borderRadius: '8px',
                      color: '#fff',
                      fontSize: '0.8rem',
                    }}
                    formatter={(value: number, name: string) => [
                      `$${value.toLocaleString('en-US', { minimumFractionDigits: 2 })}`,
                      name === 'apr' ? 'APR (Simple)' : 'APY (Compound)',
                    ]}
                  />
                  <Area
                    type="monotone"
                    dataKey="apr"
                    stroke="#4444cc"
                    strokeWidth={2}
                    fill="url(#gradAPR)"
                  />
                  <Area
                    type="monotone"
                    dataKey="apy"
                    stroke="#8888ee"
                    strokeWidth={2}
                    fill="url(#gradAPY)"
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>

            <div className="vault-chart-legend">
              <div className="vault-chart-legend-item">
                <span className="vault-chart-legend-dot" style={{ background: '#4444cc' }} />
                APR ({BTC_APR}%) — Simple
              </div>
              <div className="vault-chart-legend-item">
                <span className="vault-chart-legend-dot" style={{ background: '#8888ee' }} />
                APY ({BTC_APY}%) — Compound
              </div>
            </div>

            <div className="vault-chart-stats">
              <div className="vault-chart-stat">
                <span className="vault-chart-stat-label">Deposit</span>
                <span className="vault-chart-stat-value">
                  ${(dollarValue > 0 ? dollarValue : 10000).toLocaleString('en-US', { minimumFractionDigits: 2 })}
                </span>
              </div>
              <div className="vault-chart-stat">
                <span className="vault-chart-stat-label">Projected gain (APR)</span>
                <span className="vault-chart-stat-value purple">
                  +${projectedGainAPR.toLocaleString('en-US', { minimumFractionDigits: 2 })}
                </span>
              </div>
              <div className="vault-chart-stat">
                <span className="vault-chart-stat-label">Projected gain (APY)</span>
                <span className="vault-chart-stat-value purple">
                  +${projectedGainAPY.toLocaleString('en-US', { minimumFractionDigits: 2 })}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
