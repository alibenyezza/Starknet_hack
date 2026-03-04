import { useState, useMemo, useEffect, useRef, useCallback } from 'react';
import StarkYieldLogoBg from '@/components/ui/StarkYieldLogoBg';
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

type TxType = 'deposit' | 'withdraw' | 'faucet';

interface VaultTx {
  id: string;
  type: TxType;
  amount: number;
  txHash?: string;
  timestamp: number;
}

const TX_STORAGE_KEY = 'starkyield_vault_txs';

function loadTxs(): VaultTx[] {
  try {
    const raw = localStorage.getItem(TX_STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch { return []; }
}

function saveTxs(txs: VaultTx[]) {
  localStorage.setItem(TX_STORAGE_KEY, JSON.stringify(txs));
}

function timeAgo(ts: number): string {
  const sec = Math.floor((Date.now() - ts) / 1000);
  if (sec < 60) return `${sec}s ago`;
  const min = Math.floor(sec / 60);
  if (min < 60) return `${min}m ago`;
  const hr = Math.floor(min / 60);
  if (hr < 24) return `${hr}h ago`;
  const days = Math.floor(hr / 24);
  return `${days}d ago`;
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

export default function VaultPage({ onNavigateHome: _onNavigateHome }: VaultPageProps) {
  const vault = useVaultManager();
  const { price: realBtcPrice } = useBTCPrice();
  const { toasts, removeToast, success, error: toastError, info } = useToast();

  const [vaultMode, setVaultMode] = useState<'yield' | 'staked'>('yield');
  const [activeTab, setActiveTab] = useState<'deposit' | 'withdraw'>('deposit');
  const [amount, setAmount] = useState('');
  const [showError, setShowError] = useState(false);
  const [displayCurrency, setDisplayCurrency] = useState<'USD' | 'BTC'>('USD');
  const [chartPeriod, setChartPeriod] = useState<ChartPeriod>('3m');
  const [transactions, setTransactions] = useState<VaultTx[]>(loadTxs);
  const [txFilter, setTxFilter] = useState<'all' | TxType>('all');

  const addTx = useCallback((type: TxType, txAmount: number, txHash?: string) => {
    const tx: VaultTx = { id: crypto.randomUUID(), type, amount: txAmount, txHash, timestamp: Date.now() };
    setTransactions(prev => {
      const next = [tx, ...prev];
      saveTxs(next);
      return next;
    });
  }, []);

  // Re-render timeAgo labels every 30s
  const [, setTick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setTick(t => t + 1), 30_000);
    return () => clearInterval(id);
  }, []);

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
      const depositAmt = numericAmount;
      const res = await vault.deposit(numericAmount);
      if (res?.success) {
        addTx('deposit', depositAmt, res.txHash);
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
      const withdrawAmt = numericAmount;
      const res = await vault.withdraw(numericAmount);
      if (res?.success) {
        addTx('withdraw', withdrawAmt, res.txHash);
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
      addTx('faucet', 1, res.txHash);
      success('1 wBTC minted to your wallet!', res.txHash ? { href: `${NETWORK.EXPLORER_URL}/tx/${res.txHash}`, label: `View tx on Voyager (${res.txHash.slice(0, 10)}…)` } : undefined);
    } else {
      toastError(`Faucet failed: ${res?.error ?? 'unknown error'}`);
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

      {/* Top bar spacer */}
      <div className="vault-topbar" />

      {/* Toast notifications (local to VaultPage) */}
      <ToastContainer toasts={toasts} removeToast={removeToast} />

      {/* Two-column layout */}
      <div className="vault-layout">
        {/* Left: widget */}
        <div className="vault-widget-col">
          {/* Mode toggle */}
          <div className="vault-mode-toggle">
            <button
              className={`vault-mode-btn${vaultMode === 'yield' ? ' active' : ''}`}
              type="button"
              onClick={() => setVaultMode('yield')}
            >
              Yield Bearing Vault
            </button>
            <button
              className={`vault-mode-btn${vaultMode === 'staked' ? ' active' : ''}`}
              type="button"
              onClick={() => setVaultMode('staked')}
            >
              Staked Vault
            </button>
          </div>

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
                  {(['all', 'deposit', 'withdraw', 'faucet'] as const).map((f) => (
                    <button
                      key={f}
                      className={`vault-filter-btn${txFilter === f ? ' active' : ''}`}
                      type="button"
                      onClick={() => setTxFilter(f)}
                    >
                      {f === 'all' ? 'All' : f.charAt(0).toUpperCase() + f.slice(1)}
                    </button>
                  ))}
                </div>
              </div>
              {transactions.filter(tx => txFilter === 'all' || tx.type === txFilter).length === 0 ? (
                <div className="vault-no-transactions">No transactions found.</div>
              ) : (
                <div className="vault-tx-list">
                  {transactions
                    .filter(tx => txFilter === 'all' || tx.type === txFilter)
                    .map((tx) => (
                      <div key={tx.id} className="vault-tx-row">
                        <div className="vault-tx-icon" data-type={tx.type}>
                          {tx.type === 'deposit' ? '↓' : tx.type === 'withdraw' ? '↑' : '+'}
                        </div>
                        <div className="vault-tx-info">
                          <span className="vault-tx-type">
                            {tx.type === 'deposit' ? 'Deposit' : tx.type === 'withdraw' ? 'Withdraw' : 'Faucet'}
                          </span>
                          <span className="vault-tx-time">{timeAgo(tx.timestamp)}</span>
                        </div>
                        <div className="vault-tx-amount" data-type={tx.type}>
                          {tx.type === 'withdraw' ? '-' : '+'}{tx.amount.toFixed(4)} wBTC
                        </div>
                        {tx.txHash && (
                          <a
                            className="vault-tx-link"
                            href={`${NETWORK.EXPLORER_URL}/tx/${tx.txHash}`}
                            target="_blank"
                            rel="noopener noreferrer"
                            title="View on Voyager"
                          >
                            ↗
                          </a>
                        )}
                      </div>
                    ))}
                </div>
              )}
            </div>
          </div>

          {/* Yield Chart */}
          <div className="vault-chart-section">
            <div className="vault-chart-header">
              <div>
                <span className="vault-chart-title">
                  {chartPeriod === '1h' ? '⬤ Live Session Earnings' : 'Yield Simulation'}
                </span>
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

          </div>
        </div>
      </div>
    </div>
  );
}
