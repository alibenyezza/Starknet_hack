import { useState, useMemo, useCallback } from 'react';
import { useAccount, useDisconnect } from '@starknet-react/core';
import { HomeIcon } from '@/components/ui/icons/HomeIcon';
import StarkYieldLogoBg from '@/components/ui/StarkYieldLogoBg';
import { motion, useAnimation } from 'framer-motion';
import './VaultPage.css';

interface VaultPageProps {
  onNavigateHome?: () => void;
}

const BTC_APY = 4.12;
const USER_BALANCE = 0; // Simulated wallet balance in wBTC

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

  return (
    <div className="vault-page">
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

        {/* Right: logo */}
        <div className="vault-logo-col">
          <StarkYieldLogoBg size={700} />
        </div>
      </div>
    </div>
  );
}
