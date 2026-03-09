import { useState, useMemo, useEffect, useCallback } from 'react';
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

// StarkYield APR = 2 × r_pool − (r_borrow + r_volatility_decay)
// Protocol constants (match smart contract values)

type ChartPeriod = '24h' | '3m' | '6m' | '1y';

function generateSimulationData(depositUSD: number, period: ChartPeriod, apr: number) {
  if (period === '24h') {
    const HOURS_PER_YEAR = 8_760;
    const data = [];
    for (let i = 0; i <= 24; i++) {
      const fraction = i / HOURS_PER_YEAR;
      const gain = depositUSD * (Math.pow(1 + apr / 100, fraction) - 1);
      data.push({ x: i, gain: Math.max(0, gain) });
    }
    return data;
  }

  const months = period === '3m' ? 3 : period === '6m' ? 6 : 12;
  const compoundMonthlyRate = Math.pow(1 + apr / 100, 1 / 12) - 1;
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

  // Staked vault panel state
  const [stakedTab, setStakedTab] = useState<'stake' | 'unstake'>('stake');
  const [stakedAmount, setStakedAmount] = useState('');
  const [showStakedError, setShowStakedError] = useState(false);

  // ── Yield Bearing Vault APR (time-normalized: time-normalized all-time fees) ──
  const BLOCKS_PER_YEAR = 5_256_000; // Starknet ~6s blocks
  const yieldAPR = useMemo(() => {
    const { totalLpValue, totalDebt } = vault.vaultLpStats;
    if (totalLpValue <= 0) return 0;

    const equity = Math.max(totalLpValue - totalDebt, 1);
    const leverage = totalLpValue / equity;

    // r_pool: time-normalized — use total_fees_generated (never resets)
    // normalized by actual elapsed time since LEVAMM initialization.
    // Formula: r_pool = (totalFees / collateral) × (BLOCKS_PER_YEAR / blocksSinceInit) × 100
    const collateral = vault.levammStats.collateralValue;
    const totalFees = vault.levammStats.totalFeesGenerated;
    const initBlock = vault.levammStats.initBlock;
    const curBlock = vault.currentBlock;
    let r_pool: number;
    if (collateral > 0 && totalFees > 0 && initBlock > 0 && curBlock > initBlock) {
      const blocksSinceInit = curBlock - initBlock;
      r_pool = (totalFees / collateral) * (BLOCKS_PER_YEAR / blocksSinceInit) * 100;
    } else {
      r_pool = 0;
    }

    // r_borrow: derive from accrued interest vs debt, same time normalization
    const accInterest = vault.levammStats.accruedInterest;
    let r_borrow: number;
    if (totalDebt > 0 && accInterest > 0 && initBlock > 0 && curBlock > initBlock) {
      const blocksSinceInit = curBlock - initBlock;
      r_borrow = (accInterest / totalDebt) * (BLOCKS_PER_YEAR / blocksSinceInit) * 100;
    } else {
      r_borrow = 0;
    }

    // r_volatility_decay: rebalancing cost (rebalancing cost)
    const r_volatility_decay = r_pool > 0 ? 0.5 : 0;

    const netApr = leverage * r_pool - (r_borrow + r_volatility_decay);
    return Math.round(Math.max(netApr, 0) * 100) / 100;
  }, [vault.vaultLpStats, vault.levammStats, vault.currentBlock]);

  // ── Staked Vault APR (sy-WBTC emissions from reward_rate) ──
  const stakedAPR = useMemo(() => {
    const rate = vault.stakerStats.rewardRate; // already fromWei'd (tokens per block)
    const totalStaked = vault.stakerStats.totalStaked;
    if (rate <= 0 || totalStaked <= 0) return 12.5; // default APR when no stakers yet
    // APR = (rewardRate * blocksPerYear / totalStaked) * 100
    const apr = (rate * BLOCKS_PER_YEAR / totalStaked) * 100;
    return Math.round(Math.min(apr, 999) * 100) / 100; // cap at 999%
  }, [vault.stakerStats.rewardRate, vault.stakerStats.totalStaked]);

  // ── Active APR depends on selected vault mode ──
  const activeAPR = vaultMode === 'staked' ? stakedAPR : yieldAPR;

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

  // Sync transactions when faucet is triggered from the global menu
  useEffect(() => {
    const handler = () => setTransactions(loadTxs());
    window.addEventListener('starkyield_tx_added', handler);
    return () => window.removeEventListener('starkyield_tx_added', handler);
  }, []);

  const numericAmount = parseFloat(amount) || 0;
  const numericStakedAmount = parseFloat(stakedAmount) || 0;

  const btcPrice = realBtcPrice || vault.stats.vaultBtcPrice || 96000;
  const dollarValue = useMemo(() => numericAmount * btcPrice, [numericAmount, btcPrice]);
  const simulationBase = useMemo(
    () => dollarValue > 0 ? dollarValue : vault.userDepositBTC > 0 ? vault.userDepositBTC * btcPrice : 10000,
    [dollarValue, vault.userDepositBTC, btcPrice]
  );
  const depositedUSD = useMemo(() => vault.userDepositBTC * btcPrice, [vault.userDepositBTC, btcPrice]);
  const monthlyEarnings = useMemo(() => (depositedUSD * activeAPR) / 100 / 12, [depositedUSD, activeAPR]);
  const yearlyEarnings = useMemo(() => (depositedUSD * activeAPR) / 100, [depositedUSD, activeAPR]);

  // Track elapsed time for 24h chart "Now" marker
  const [elapsedMs, setElapsedMs] = useState(0);
  useEffect(() => {
    const start = Date.now();
    const id = setInterval(() => setElapsedMs(Date.now() - start), 60_000);
    return () => clearInterval(id);
  }, []);
  const elapsedHours = elapsedMs / 3_600_000;

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

  const handleStakedAmountChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = e.target.value;
    if (val === '' || /^\d*\.?\d*$/.test(val)) {
      setStakedAmount(val);
      setShowStakedError(false);
    }
  };

  const handleAction = async () => {
    if (activeTab === 'deposit') {
      if (numericAmount <= 0) return;
      if (numericAmount > vault.wbtcBalance) { setShowError(true); return; }
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
      if (numericAmount > vault.userDepositBTC) { setShowError(true); return; }
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

  const handleStakeAction = async () => {
    if (stakedTab === 'stake') {
      if (numericStakedAmount <= 0) return;
      if (numericStakedAmount > vault.wbtcBalance) { setShowStakedError(true); return; }
      setShowStakedError(false);
      info('Depositing & staking wBTC — approve in your wallet…');
      const res = await vault.depositAndStake(numericStakedAmount);
      if (res?.success) {
        success('wBTC deposited & staked!', res.txHash ? { href: `${NETWORK.EXPLORER_URL}/tx/${res.txHash}`, label: `View tx on Voyager (${res.txHash.slice(0, 10)}…)` } : undefined);
        setStakedAmount('');
      } else {
        toastError(`Stake failed: ${res?.error ?? 'unknown error'}`);
      }
    } else {
      if (numericStakedAmount <= 0 || vault.stakerStats.userStaked === 0) return;
      if (numericStakedAmount > vault.stakerStats.userStaked) { setShowStakedError(true); return; }
      setShowStakedError(false);
      info('Unstaking & withdrawing wBTC — approve in your wallet…');
      const res = await vault.unstakeAndWithdraw(numericStakedAmount);
      if (res?.success) {
        success('wBTC unstaked & withdrawn!', res.txHash ? { href: `${NETWORK.EXPLORER_URL}/tx/${res.txHash}`, label: `View tx on Voyager (${res.txHash.slice(0, 10)}…)` } : undefined);
        setStakedAmount('');
      } else {
        toastError(`Unstake failed: ${res?.error ?? 'unknown error'}`);
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

  const isStakeDisabled =
    stakedTab === 'stake'
      ? numericStakedAmount <= 0 || vault.isStaking
      : numericStakedAmount <= 0 || vault.stakerStats.userStaked === 0 || vault.isUnstaking;

  const simulationData = useMemo(
    () => generateSimulationData(simulationBase, chartPeriod, activeAPR),
    [simulationBase, chartPeriod, activeAPR]
  );

  const projectedGain = useMemo(() => {
    const last = simulationData[simulationData.length - 1];
    return (last as { gain?: number }).gain ?? 0;
  }, [simulationData]);

  // Staked balance depending on tab
  const stakedDisplayBalance = stakedTab === 'stake'
    ? vault.wbtcBalance
    : vault.stakerStats.userStaked;
  const stakedBalanceLabel = stakedTab === 'stake' ? 'wBTC balance' : 'wBTC staked';

  return (
    <div className="vault-page">
      <div className="vault-bg-logo">
        <StarkYieldLogoBg size={700} />
      </div>

      <div className="vault-topbar" />

      <ToastContainer toasts={toasts} removeToast={removeToast} />

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

          {/* ── YIELD BEARING VAULT PANEL ── */}
          {vaultMode === 'yield' && (
            <div className="vault-panel">
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
                      <>
                        <button
                          className="vault-max-btn"
                          type="button"
                          onClick={handleFaucet}
                          disabled={vault.isFauceting}
                          style={{ marginLeft: '0.4rem', opacity: vault.isFauceting ? 0.6 : 1 }}
                        >
                          {vault.isFauceting ? 'Minting…' : 'Faucet +1 wBTC'}
                        </button>
                        {vault.wbtcBalance > 100 && (
                          <button
                            className="vault-max-btn"
                            type="button"
                            onClick={async () => {
                              const res = await vault.burnWbtc();
                              if (!res.success) console.error('Burn failed:', res.error);
                            }}
                            style={{ marginLeft: '0.4rem', color: '#ff6b6b' }}
                          >
                            Burn All
                          </button>
                        )}
                      </>
                    )}
                  </div>
                </div>
              </div>

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

              <div className="vault-summary">
                <div className="vault-summary-row">
                  <div className="vault-summary-left">
                    <span className="vault-summary-label">
                      {activeTab === 'deposit' ? 'Deposit' : 'Withdraw'} (wBTC)
                    </span>
                  </div>
                  <span className="vault-summary-value">{numericAmount.toFixed(2)}</span>
                </div>
                <div className="vault-summary-row">
                  <span className="vault-summary-label">APR</span>
                  <span className="vault-summary-value vault-apy">
                    {yieldAPR}%{yieldAPR === 0 && <span style={{ color: 'rgba(255,255,255,0.35)', fontSize: '0.75rem', marginLeft: '0.4rem' }}>(no trades)</span>}
                  </span>
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

              {/* ── Claimable Fees (LT holders) ── */}
              {vault.claimableFees > 0 && (
                <div style={{
                  background: 'rgba(74,222,128,0.10)',
                  border: '1px solid rgba(74,222,128,0.25)',
                  borderRadius: '10px',
                  padding: '0.75rem 1rem',
                  marginTop: '0.75rem',
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                }}>
                  <div>
                    <div style={{ color: 'rgba(255,255,255,0.5)', fontSize: '0.75rem' }}>Claimable Fees (USDC)</div>
                    <div style={{ color: '#4ade80', fontWeight: 600, fontSize: '1.1rem' }}>
                      ${vault.claimableFees.toFixed(2)}
                    </div>
                  </div>
                  <button
                    className="vault-max-btn"
                    type="button"
                    style={{
                      background: '#4ade80',
                      color: '#000',
                      padding: '0.4rem 1rem',
                      borderRadius: '8px',
                      fontWeight: 600,
                      fontSize: '0.85rem',
                      opacity: vault.isClaimingFees ? 0.6 : 1,
                    }}
                    disabled={vault.isClaimingFees}
                    onClick={async () => {
                      const res = await vault.claimFees();
                      if (res?.success) {
                        success('USDC fees claimed!', res.txHash ? { href: `${NETWORK.EXPLORER_URL}/tx/${res.txHash}`, label: `View tx` } : undefined);
                      } else {
                        toastError(`Claim fees failed: ${res?.error ?? 'unknown'}`);
                      }
                    }}
                  >
                    {vault.isClaimingFees ? 'Claiming…' : 'Claim USDC'}
                  </button>
                </div>
              )}

              {/* ── Harvest Fees (permissionless) ── */}
              <div style={{ display: 'flex', gap: '0.5rem', marginTop: '0.75rem' }}>
                <button
                  className="vault-max-btn"
                  type="button"
                  style={{
                    flex: 1,
                    padding: '0.5rem',
                    borderRadius: '8px',
                    fontSize: '0.8rem',
                    fontWeight: 600,
                    color: '#a78bfa',
                    background: 'rgba(167,139,250,0.08)',
                    border: '1px solid rgba(167,139,250,0.25)',
                    opacity: vault.isCollectingFees ? 0.6 : 1,
                  }}
                  disabled={vault.isCollectingFees}
                  onClick={async () => {
                    info('Collecting trading fees…');
                    const res = await vault.collectFees();
                    if (res?.success) {
                      success('Fees collected from LEVAMM!', res.txHash ? { href: `${NETWORK.EXPLORER_URL}/tx/${res.txHash}`, label: `View tx` } : undefined);
                    } else {
                      toastError(`Collect fees failed: ${res?.error ?? 'unknown'}`);
                    }
                  }}
                >
                  {vault.isCollectingFees ? 'Collecting…' : 'Collect Fees'}
                </button>
                {vault.accumulatedHolderFees > 0 && (
                  <button
                    className="vault-max-btn"
                    type="button"
                    style={{
                      flex: 1,
                      padding: '0.5rem',
                      borderRadius: '8px',
                      fontSize: '0.8rem',
                      fontWeight: 600,
                      color: '#a78bfa',
                      background: 'rgba(167,139,250,0.08)',
                      border: '1px solid rgba(167,139,250,0.25)',
                    }}
                    onClick={async () => {
                      info('Harvesting fees to LT holders…');
                      const res = await vault.harvestFees();
                      if (res?.success) {
                        success('Fees distributed to LT token!', res.txHash ? { href: `${NETWORK.EXPLORER_URL}/tx/${res.txHash}`, label: `View tx` } : undefined);
                      } else {
                        toastError(`Harvest failed: ${res?.error ?? 'unknown'}`);
                      }
                    }}
                  >
                    Harvest (${vault.accumulatedHolderFees.toFixed(2)})
                  </button>
                )}
              </div>

              <p className="vault-disclaimer">
                Smart contracts are unaudited. Sepolia testnet only.{' '}
                <a
                  href={`${NETWORK.EXPLORER_URL}/contract/${CONTRACTS.VAULT_MANAGER}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  style={{ color: 'rgba(167,139,250,0.7)', textDecoration: 'underline' }}
                >
                  Verify on Voyager ↗
                </a>
              </p>
            </div>
          )}

          {/* ── STAKED VAULT PANEL ── */}
          {vaultMode === 'staked' && (
            <div className="vault-panel">
              {/* Stake / Unstake tabs */}
              <div className="vault-tabs">
                <button
                  className={`vault-tab${stakedTab === 'stake' ? ' active' : ''}`}
                  onClick={() => { setStakedTab('stake'); setStakedAmount(''); setShowStakedError(false); }}
                  type="button"
                >
                  Stake
                </button>
                <button
                  className={`vault-tab${stakedTab === 'unstake' ? ' active' : ''}`}
                  onClick={() => { setStakedTab('unstake'); setStakedAmount(''); setShowStakedError(false); }}
                  type="button"
                >
                  Unstake
                </button>
              </div>

              {/* Rewards banner removed — no sy-WBTC rewards in v12 */}

              {/* Input */}
              <div className="vault-input-card">
                <div className="vault-input-header">
                  <span className="vault-input-title">
                    {stakedTab === 'stake' ? 'Stake wBTC' : 'Unstake wBTC'}
                  </span>
                </div>
                <div className="vault-input-field">
                  <input
                    aria-label="Stake Amount"
                    placeholder="0.00"
                    inputMode="decimal"
                    className="vault-amount-input"
                    value={stakedAmount}
                    onChange={handleStakedAmountChange}
                  />
                </div>
                <div className="vault-input-footer">
                  <span className="vault-dollar-value">
                    ${(numericStakedAmount * btcPrice).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                  </span>
                  <div className="vault-balance-row">
                    <span className="vault-balance-label">
                      {stakedDisplayBalance.toFixed(4)} {stakedBalanceLabel}
                    </span>
                    <button
                      className="vault-max-btn"
                      type="button"
                      onClick={() => setStakedAmount(String(Math.floor(stakedDisplayBalance * 1e6) / 1e6))}
                    >
                      MAX
                    </button>
                    {stakedTab === 'stake' && (
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

              {showStakedError && (
                <div className="vault-error-msg">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <circle cx="12" cy="12" r="10" />
                    <line x1="12" y1="8" x2="12" y2="12" />
                    <line x1="12" y1="16" x2="12.01" y2="16" />
                  </svg>
                  <span>
                    {stakedTab === 'stake'
                      ? `Insufficient wBTC balance. You have ${vault.wbtcBalance.toFixed(4)} wBTC available.`
                      : `You only have ${vault.stakerStats.userStaked.toFixed(4)} wBTC staked.`}
                  </span>
                </div>
              )}

              {/* Staking summary */}
              <div className="vault-summary">
                <div className="vault-summary-row">
                  <span className="vault-summary-label">APR <span style={{ color: 'rgba(255,255,255,0.35)', fontSize: '0.75rem' }}>(sy-WBTC emissions)</span></span>
                  <span className="vault-summary-value vault-apy">{stakedAPR}%</span>
                </div>
                <div className="vault-summary-row">
                  <span className="vault-summary-label">Your staked position</span>
                  <span className="vault-summary-value">
                    {vault.stakerStats.userStaked.toFixed(4)} wBTC
                  </span>
                </div>
                <div className="vault-summary-row">
                  <span className="vault-summary-label">Pending rewards</span>
                  <span className="vault-summary-value" style={{ color: vault.stakerStats.pendingRewards > 0.000001 ? '#a78bfa' : undefined }}>
                    {vault.stakerStats.pendingRewards.toFixed(6)} sy-WBTC
                  </span>
                </div>
                <div className="vault-summary-row">
                  <span className="vault-summary-label">Total staked (protocol)</span>
                  <span className="vault-summary-value">
                    {vault.stakerStats.totalStaked.toFixed(4)} wBTC
                  </span>
                </div>
              </div>

              <button
                className="vault-action-btn"
                disabled={isStakeDisabled}
                type="button"
                onClick={handleStakeAction}
              >
                {vault.isStaking
                  ? 'Staking…'
                  : vault.isUnstaking
                    ? 'Unstaking…'
                    : isStakeDisabled
                      ? stakedTab === 'stake' ? 'Enter an amount' : 'Nothing to unstake'
                      : stakedTab === 'stake'
                        ? 'Stake wBTC'
                        : 'Unstake wBTC'}
              </button>

              {/* ── Claim Rewards (same position as Collect Fees in yield vault) ── */}
              {vault.stakerStats.pendingRewards > 0.000001 && (
                <div style={{ display: 'flex', gap: '0.5rem', marginTop: '0.75rem' }}>
                  <button
                    className="vault-max-btn"
                    type="button"
                    style={{
                      flex: 1,
                      padding: '0.5rem',
                      borderRadius: '8px',
                      fontSize: '0.8rem',
                      fontWeight: 600,
                      color: '#a78bfa',
                      background: 'rgba(167,139,250,0.08)',
                      border: '1px solid rgba(167,139,250,0.25)',
                      opacity: vault.isClaimingRewards ? 0.6 : 1,
                    }}
                    disabled={vault.isClaimingRewards}
                    onClick={async () => {
                      const res = await vault.claimRewards();
                      if (res?.success) {
                        success('sy-WBTC rewards claimed!', res.txHash ? { href: `${NETWORK.EXPLORER_URL}/tx/${res.txHash}`, label: `View tx` } : undefined);
                      } else {
                        toastError(`Claim failed: ${res?.error ?? 'unknown'}`);
                      }
                    }}
                  >
                    {vault.isClaimingRewards ? 'Claiming…' : `Claim Rewards (${vault.stakerStats.pendingRewards.toFixed(6)} sy-WBTC)`}
                  </button>
                </div>
              )}

              {vault.stakerStats.userStaked === 0 && (
                <p className="vault-disclaimer">
                  Stake wBTC to earn sy-WBTC emissions and boost your yield.
                </p>
              )}

              <p className="vault-disclaimer" style={{ marginTop: vault.stakerStats.userStaked === 0 ? '0' : undefined }}>
                Smart contracts are unaudited. Sepolia testnet only.{' '}
                <a
                  href={`${NETWORK.EXPLORER_URL}/contract/${CONTRACTS.STAKER}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  style={{ color: 'rgba(167,139,250,0.7)', textDecoration: 'underline' }}
                >
                  Verify on Voyager ↗
                </a>
              </p>
            </div>
          )}
        </div>

        {/* Right column: position + chart */}
        <div className="vault-right-col">
          {/* My Position */}
          <div className="vault-position-section">
            <div className="vault-position-header">
              <span className="vault-position-title">
                {vaultMode === 'staked' ? 'My Staked Position' : 'My Deposit'}
              </span>
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
                {vaultMode === 'staked'
                  ? (displayCurrency === 'USD'
                      ? `$${(vault.stakerStats.userStaked * btcPrice).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
                      : vault.stakerStats.userStaked.toFixed(6))
                  : (displayCurrency === 'USD'
                      ? `$${(vault.userDepositBTC * btcPrice).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
                      : vault.userDepositBTC.toFixed(6))}
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
                  Yield Simulation
                </span>
              </div>
              <div className="vault-chart-controls">
                {(['24h', '3m', '6m', '1y'] as ChartPeriod[]).map((p) => (
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
                  <AreaChart data={simulationData} margin={{ top: 5, right: 10, left: 0, bottom: 0 }}>
                    <defs>
                      <linearGradient id="gradGain" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor={vaultMode === 'staked' ? '#a78bfa' : '#a78bfa'} stopOpacity={0.35} />
                        <stop offset="100%" stopColor={vaultMode === 'staked' ? '#a78bfa' : '#a78bfa'} stopOpacity={0.02} />
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
                      tick={{ fill: 'rgba(255,255,255,0.5)', fontSize: 11 }}
                      axisLine={{ stroke: 'rgba(255,255,255,0.08)' }}
                      tickLine={{ stroke: 'rgba(255,255,255,0.08)' }}
                      tickFormatter={(v: number) => v === 0 ? '$0' : fmtDollar(v)}
                      domain={[0, 'auto']}
                      width={60}
                    />
                    <Tooltip
                      contentStyle={{ background: 'rgba(20,20,30,0.95)', border: '1px solid rgba(255,255,255,0.1)', borderRadius: '8px', color: '#fff', fontSize: '0.8rem' }}
                      formatter={(value: number) => [fmtDollar(value), `Yield earned (${activeAPR}% APR)`]}
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
              </ResponsiveContainer>
            </div>

            <div className="vault-chart-legend">
              <div className="vault-chart-legend-item">
                <span className="vault-chart-legend-dot" style={{ background: '#a78bfa' }} />
                Projected yield at {activeAPR}% APR
              </div>
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
                  Projected yield over {chartPeriod === '24h' ? '24 hours' : chartPeriod === '3m' ? '3 months' : chartPeriod === '6m' ? '6 months' : '1 year'}
                </span>
                <span className="vault-chart-stat-value purple">
                  +{fmtDollar(projectedGain)}
                </span>
              </div>
              <div className="vault-chart-stat">
                <span className="vault-chart-stat-label">
                  Portfolio after {chartPeriod === '24h' ? '24 hours' : chartPeriod === '3m' ? '3 months' : chartPeriod === '6m' ? '6 months' : '1 year'}
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
