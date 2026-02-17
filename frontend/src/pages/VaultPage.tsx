import { useState } from 'react';
import { useAccount, useDisconnect } from '@starknet-react/core';
import StarBorder from '@/components/ui/StarBorder';
import { HomeIcon } from '@/components/ui/icons/HomeIcon';
import './VaultPage.css';

interface VaultPageProps {
  onNavigateHome?: () => void;
}

type Strategy = 'auto' | 'ekubo' | 'vesu' | 'endur';

const strategies: { id: Strategy; label: string; desc: string }[] = [
  { id: 'auto', label: 'Auto', desc: 'Optimized across all protocols' },
  { id: 'ekubo', label: 'Ekubo DEX', desc: 'Concentrated liquidity' },
  { id: 'vesu', label: 'Vesu Lending', desc: 'Stable lending yield' },
  { id: 'endur', label: 'Endur', desc: 'Liquid staking' },
];

export default function VaultPage({ onNavigateHome }: VaultPageProps) {
  const { address } = useAccount();
  const { disconnect } = useDisconnect();
  const [activeTab, setActiveTab] = useState<'deposit' | 'withdraw'>('deposit');
  const [amount, setAmount] = useState('');
  const [strategy, setStrategy] = useState<Strategy>('auto');

  const shortAddress = address
    ? `${String(address).slice(0, 6)}...${String(address).slice(-4)}`
    : '';

  const handleDisconnect = () => {
    disconnect();
    onNavigateHome?.();
  };

  return (
    <div className="vault-page">
      {/* Top bar: home + disconnect */}
      <div className="vault-topbar">
        <button className="vault-back-btn" onClick={onNavigateHome} type="button">
          <HomeIcon size={18} />
          Home
        </button>
        <button className="vault-disconnect-btn" onClick={handleDisconnect} type="button">
          Disconnect
        </button>
      </div>

      <div className="vault-container">
        {/* Badge + title */}
        <div className="vault-header">
          <div className="vault-badge">BTC Yield Vault</div>
          <h1 className="vault-title">Deposit & Earn</h1>
          <p className="vault-subtitle">
            Deposit wBTC into the StarkYield vault and earn optimized yield — automatically.
          </p>
          {shortAddress && (
            <div className="vault-wallet-row">
              <span className="vault-wallet-dot" />
              <span className="vault-wallet-addr">{shortAddress}</span>
            </div>
          )}
        </div>

        {/* Form card */}
        <div className="vault-form-card">
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

          {/* Amount input */}
          <div className="vault-input-group">
            <label className="vault-input-label">
              {activeTab === 'deposit' ? 'wBTC Amount' : 'syBTC Shares to Redeem'}
            </label>
            <div className="vault-input-row">
              <input
                type="number"
                className="vault-input"
                placeholder="0.000"
                value={amount}
                onChange={e => setAmount(e.target.value)}
                min="0"
                step="0.001"
              />
              <button
                className="vault-max-btn"
                type="button"
                onClick={() => setAmount('0.001')}
              >
                MAX
              </button>
            </div>
            <div className="vault-input-hint">
              Minimum: 0.001 wBTC &nbsp;·&nbsp; Balance: 0.000 wBTC
            </div>
          </div>

          {/* Strategy selector */}
          <div className="vault-strategy-group">
            <div className="vault-input-label">Strategy</div>
            <div className="vault-strategy-grid">
              {strategies.map(s => (
                <button
                  key={s.id}
                  className={`vault-strategy-btn${strategy === s.id ? ' active' : ''}`}
                  onClick={() => setStrategy(s.id)}
                  type="button"
                >
                  <span className="vault-strategy-label">{s.label}</span>
                  <span className="vault-strategy-desc">{s.desc}</span>
                </button>
              ))}
            </div>
          </div>

          {/* Action button */}
          <div style={{ display: 'flex', justifyContent: 'center', marginTop: '1.5rem' }}>
            <StarBorder as="button" color="#4444cc" speed="4s">
              <span style={{ fontWeight: 600, fontSize: '0.95rem' }}>
                {activeTab === 'deposit' ? 'Deposit wBTC' : 'Withdraw wBTC'}
              </span>
            </StarBorder>
          </div>

          <p className="vault-disclaimer">
            Smart contracts are unaudited. Do not deposit significant mainnet funds.
          </p>
        </div>
      </div>
    </div>
  );
}
