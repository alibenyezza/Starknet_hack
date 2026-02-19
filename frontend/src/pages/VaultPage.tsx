import { useState, useCallback } from 'react';
import { useAccount, useDisconnect } from '@starknet-react/core';
import StarBorder from '@/components/ui/StarBorder';
import { HomeIcon } from '@/components/ui/icons/HomeIcon';
import { useVaultManager } from '@/hooks/useVaultManager';
import { useERC20 } from '@/hooks/useERC20';
import { DECIMALS, HEALTH_FACTOR, CONTRACTS, NETWORK } from '@/config/constants';
import { uint256, CallData, RpcProvider } from 'starknet';
import './VaultPage.css';

interface VaultPageProps {
  onNavigateHome?: () => void;
  onToast?: (message: string, type: 'success' | 'error' | 'info' | 'warning') => void;
}

type Strategy = 'auto' | 'ekubo' | 'vesu' | 'endur';

const strategies: { id: Strategy; label: string; desc: string }[] = [
  { id: 'auto', label: 'Auto', desc: 'Optimized across all protocols' },
  { id: 'ekubo', label: 'Ekubo DEX', desc: 'Concentrated liquidity' },
  { id: 'vesu', label: 'Vesu Lending', desc: 'Stable lending yield' },
  { id: 'endur', label: 'Endur', desc: 'Liquid staking' },
];

const SCALE = BigInt('1000000000000000000'); // 1e18

function formatFromScale(value: bigint, decimals: number = 4): string {
  const num = Number(value) / Number(SCALE);
  return num.toFixed(decimals);
}

function formatBtcBalance(value: bigint): string {
  const num = Number(value) / 10 ** DECIMALS.BTC;
  return num.toFixed(6);
}

function parseBtcToRaw(input: string): bigint {
  const num = parseFloat(input);
  if (isNaN(num) || num <= 0) return 0n;
  return BigInt(Math.floor(num * 10 ** DECIMALS.BTC));
}

function parseSharesToRaw(input: string): bigint {
  const num = parseFloat(input);
  if (isNaN(num) || num <= 0) return 0n;
  return BigInt(Math.floor(num * 10 ** DECIMALS.SHARES));
}

function formatShares(value: bigint): string {
  const num = Number(value) / 10 ** DECIMALS.SHARES;
  return num.toFixed(6);
}

function getHealthColor(hf: bigint): string {
  const hfNum = Number(hf) / Number(SCALE);
  if (hfNum >= HEALTH_FACTOR.SAFE) return '#4ade80';
  if (hfNum >= HEALTH_FACTOR.MODERATE) return '#facc15';
  if (hfNum >= HEALTH_FACTOR.WARNING) return '#fb923c';
  return '#ef4444';
}

function getHealthLabel(hf: bigint): string {
  const hfNum = Number(hf) / Number(SCALE);
  if (hfNum >= HEALTH_FACTOR.SAFE) return 'Safe';
  if (hfNum >= HEALTH_FACTOR.MODERATE) return 'Moderate';
  if (hfNum >= HEALTH_FACTOR.WARNING) return 'Warning';
  return 'Danger';
}

export default function VaultPage({ onNavigateHome, onToast }: VaultPageProps) {
  const { account, address } = useAccount();
  const { disconnect } = useDisconnect();
  const [activeTab, setActiveTab] = useState<'deposit' | 'withdraw'>('deposit');
  const [amount, setAmount] = useState('');
  const [strategy, setStrategy] = useState<Strategy>('auto');
  const [faucetLoading, setFaucetLoading] = useState(false);

  const vault = useVaultManager();
  const erc20 = useERC20();

  const toast = useCallback(
    (msg: string, type: 'success' | 'error' | 'info' | 'warning' = 'info') => {
      onToast?.(msg, type);
    },
    [onToast]
  );

  const shortAddress = address
    ? `${String(address).slice(0, 6)}...${String(address).slice(-4)}`
    : '';

  const handleDisconnect = () => {
    disconnect();
    onNavigateHome?.();
  };

  const handleFaucet = async () => {
    if (!account) return;
    setFaucetLoading(true);
    try {
      console.log('=== FAUCET START ===');
      console.log('Account address:', address);
      console.log('BTC_TOKEN contract:', CONTRACTS.BTC_TOKEN);
      toast('Minting 1 wBTC from faucet...', 'info');
      const faucetAmount = uint256.bnToUint256(BigInt('1000000000000000000')); // 1 wBTC (18 decimals)
      console.log('Faucet calldata:', faucetAmount);
      const provider = new RpcProvider({ nodeUrl: NETWORK.RPC_URL });
      const result = await account.execute([
        {
          contractAddress: CONTRACTS.BTC_TOKEN,
          entrypoint: 'faucet',
          calldata: CallData.compile({ amount: faucetAmount }),
        },
      ]);
      console.log('Faucet tx hash:', result.transaction_hash);
      console.log('Waiting for tx...');
      const receipt = await provider.waitForTransaction(result.transaction_hash);
      console.log('Faucet tx receipt:', receipt);
      console.log('Tx status:', (receipt as any).execution_status || (receipt as any).status);
      toast('Faucet success! 1 wBTC minted', 'success');
      await new Promise(r => setTimeout(r, 3000));
      erc20.refetch();
      vault.refetch();
    } catch (err: any) {
      console.error('=== FAUCET ERROR ===', err);
      const msg = err?.message || 'Faucet failed';
      if (msg.includes('User abort') || msg.includes('rejected')) {
        toast('Transaction rejected', 'warning');
      } else {
        toast(`Faucet failed: ${msg.slice(0, 120)}`, 'error');
      }
    } finally {
      setFaucetLoading(false);
    }
  };

  const handleMaxClick = () => {
    if (activeTab === 'deposit') {
      setAmount(formatBtcBalance(erc20.balance));
    } else {
      setAmount(formatShares(vault.userShares));
    }
  };

  const handleDeposit = async () => {
    const rawAmount = parseBtcToRaw(amount);
    if (rawAmount <= 0n) {
      toast('Enter a valid amount', 'warning');
      return;
    }
    if (rawAmount > erc20.balance) {
      toast('Insufficient wBTC balance', 'error');
      return;
    }

    try {
      // Check allowance, approve if needed
      if (erc20.allowance < rawAmount) {
        toast('Approving wBTC...', 'info');
        await erc20.approve(rawAmount);
        toast('Approval confirmed!', 'success');
      }

      toast('Depositing wBTC...', 'info');
      const txHash = await vault.deposit(rawAmount);
      if (txHash) {
        toast(`Deposit successful! Tx: ${txHash.slice(0, 10)}...`, 'success');
      }
      setAmount('');
    } catch (err: any) {
      const msg = err?.message || 'Transaction failed';
      if (msg.includes('User abort') || msg.includes('rejected')) {
        toast('Transaction rejected by user', 'warning');
      } else {
        toast(`Deposit failed: ${msg.slice(0, 80)}`, 'error');
      }
    }
  };

  const handleWithdraw = async () => {
    const rawShares = parseSharesToRaw(amount);
    if (rawShares <= 0n) {
      toast('Enter a valid amount', 'warning');
      return;
    }
    if (rawShares > vault.userShares) {
      toast('Insufficient syBTC shares', 'error');
      return;
    }

    try {
      toast('Withdrawing...', 'info');
      const txHash = await vault.withdraw(rawShares);
      if (txHash) {
        toast(`Withdrawal successful! Tx: ${txHash.slice(0, 10)}...`, 'success');
      }
      setAmount('');
    } catch (err: any) {
      const msg = err?.message || 'Transaction failed';
      if (msg.includes('User abort') || msg.includes('rejected')) {
        toast('Transaction rejected by user', 'warning');
      } else {
        toast(`Withdrawal failed: ${msg.slice(0, 80)}`, 'error');
      }
    }
  };

  const handleAction = () => {
    if (activeTab === 'deposit') {
      handleDeposit();
    } else {
      handleWithdraw();
    }
  };

  const isBusy = vault.txLoading || erc20.txLoading || faucetLoading;
  const leverageNum = Number(vault.currentLeverage) / Number(SCALE);
  const healthNum = Number(vault.healthFactor) / Number(SCALE);

  return (
    <div className="vault-page">
      {/* Top bar */}
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

        {/* Vault Stats */}
        <div className="vault-stats-grid">
          <div className="vault-stat-card">
            <span className="vault-stat-label">Your Position</span>
            <span className="vault-stat-value">{formatShares(vault.userShares)} syBTC</span>
            <span className="vault-stat-sub">
              ~ {formatFromScale(vault.userShares * vault.sharePrice / SCALE, 6)} BTC
            </span>
          </div>
          <div className="vault-stat-card">
            <span className="vault-stat-label">Share Price</span>
            <span className="vault-stat-value">{formatFromScale(vault.sharePrice, 6)} BTC</span>
          </div>
          <div className="vault-stat-card">
            <span className="vault-stat-label">Total Assets</span>
            <span className="vault-stat-value">{formatFromScale(vault.totalAssets, 4)} BTC</span>
          </div>
          <div className="vault-stat-card">
            <span className="vault-stat-label">Health Factor</span>
            <span
              className="vault-stat-value"
              style={{ color: getHealthColor(vault.healthFactor) }}
            >
              {healthNum > 100 ? '---' : healthNum.toFixed(2)}
            </span>
            <span
              className="vault-stat-sub"
              style={{ color: getHealthColor(vault.healthFactor) }}
            >
              {healthNum > 100 ? 'No debt' : getHealthLabel(vault.healthFactor)}
            </span>
          </div>
          <div className="vault-stat-card">
            <span className="vault-stat-label">Leverage</span>
            <span className="vault-stat-value">{leverageNum.toFixed(2)}x</span>
          </div>
          <div className="vault-stat-card">
            <span className="vault-stat-label">wBTC Balance</span>
            <span className="vault-stat-value">{formatBtcBalance(erc20.balance)}</span>
            <button
              className="vault-faucet-btn"
              onClick={handleFaucet}
              disabled={faucetLoading || isBusy}
              type="button"
            >
              {faucetLoading ? 'Minting...' : 'Faucet 1 wBTC'}
            </button>
          </div>
        </div>

        {/* Form card */}
        <div className="vault-form-card">
          {/* Tabs */}
          <div className="vault-tabs">
            <button
              className={`vault-tab${activeTab === 'deposit' ? ' active' : ''}`}
              onClick={() => { setActiveTab('deposit'); setAmount(''); }}
              type="button"
            >
              Deposit
            </button>
            <button
              className={`vault-tab${activeTab === 'withdraw' ? ' active' : ''}`}
              onClick={() => { setActiveTab('withdraw'); setAmount(''); }}
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
                disabled={isBusy}
              />
              <button
                className="vault-max-btn"
                type="button"
                onClick={handleMaxClick}
                disabled={isBusy}
              >
                MAX
              </button>
            </div>
            <div className="vault-input-hint">
              {activeTab === 'deposit' ? (
                <>
                  Minimum: 0.001 wBTC &nbsp;&middot;&nbsp; Balance: {formatBtcBalance(erc20.balance)} wBTC
                </>
              ) : (
                <>
                  Available: {formatShares(vault.userShares)} syBTC
                </>
              )}
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
                  disabled={isBusy}
                >
                  <span className="vault-strategy-label">{s.label}</span>
                  <span className="vault-strategy-desc">{s.desc}</span>
                </button>
              ))}
            </div>
          </div>

          {/* Action button */}
          <div style={{ display: 'flex', justifyContent: 'center', marginTop: '1.5rem' }}>
            <StarBorder
              as="button"
              color={isBusy ? '#666' : '#4444cc'}
              speed="4s"
              onClick={handleAction}
              style={{ opacity: isBusy ? 0.6 : 1, cursor: isBusy ? 'not-allowed' : 'pointer' }}
            >
              <span style={{ fontWeight: 600, fontSize: '0.95rem' }}>
                {isBusy
                  ? 'Processing...'
                  : activeTab === 'deposit'
                  ? 'Deposit wBTC'
                  : 'Withdraw wBTC'}
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
