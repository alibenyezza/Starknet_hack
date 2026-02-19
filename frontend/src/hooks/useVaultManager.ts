import { useState, useEffect, useCallback } from 'react';
import { useAccount } from '@starknet-react/core';
import { RpcProvider, uint256, CallData } from 'starknet';
import { CONTRACTS, NETWORK, APP_CONFIG } from '@/config/constants';

const SCALE = BigInt('1000000000000000000'); // 1e18

function parseFelt(result: string[]): bigint {
  if (!result || result.length === 0) return 0n;
  return BigInt(result[0]);
}

function parseU256(result: string[]): bigint {
  if (!result || result.length < 2) return 0n;
  return uint256.uint256ToBN({ low: result[0], high: result[1] });
}

interface VaultData {
  sharePrice: bigint;
  totalAssets: bigint;
  totalShares: bigint;
  userShares: bigint;
  healthFactor: bigint;
  btcPrice: bigint;
  currentLeverage: bigint;
}

const defaultData: VaultData = {
  sharePrice: SCALE,
  totalAssets: 0n,
  totalShares: 0n,
  userShares: 0n,
  healthFactor: 999n * SCALE,
  btcPrice: 60000n * SCALE,
  currentLeverage: SCALE,
};

export function useVaultManager() {
  const { account, address } = useAccount();
  const [data, setData] = useState<VaultData>(defaultData);
  const [isLoading, setIsLoading] = useState(false);
  const [txLoading, setTxLoading] = useState(false);

  const provider = new RpcProvider({ nodeUrl: NETWORK.RPC_URL });

  const callView = useCallback(
    async (fnName: string, calldata: string[] = []): Promise<string[]> => {
      try {
        return await provider.callContract(
          { contractAddress: CONTRACTS.VAULT_MANAGER, entrypoint: fnName, calldata },
          'latest'
        );
      } catch {
        return [];
      }
    },
    []
  );

  // Fetch all view data
  const refetch = useCallback(async () => {
    try {
      setIsLoading(true);

      const [
        sharePriceR,
        totalAssetsR,
        totalSharesR,
        healthFactorR,
        btcPriceR,
        currentLeverageR,
      ] = await Promise.all([
        callView('get_share_price'),
        callView('get_total_assets'),
        callView('get_total_shares'),
        callView('get_health_factor'),
        callView('get_btc_price'),
        callView('get_current_leverage'),
      ]);

      let userSharesR: string[] = [];
      if (address) {
        userSharesR = await callView('get_user_shares', [address]);
      }

      console.log('Vault raw share_price:', sharePriceR, 'total_assets:', totalAssetsR);

      setData({
        sharePrice: parseU256(sharePriceR) || SCALE,
        totalAssets: parseU256(totalAssetsR),
        totalShares: parseU256(totalSharesR),
        userShares: parseU256(userSharesR),
        healthFactor: parseFelt(healthFactorR) || 999n * SCALE,
        btcPrice: parseFelt(btcPriceR) || 60000n * SCALE,
        currentLeverage: parseFelt(currentLeverageR) || SCALE,
      });
    } catch (err) {
      console.error('Failed to fetch vault data:', err);
    } finally {
      setIsLoading(false);
    }
  }, [address, callView]);

  // Auto-refresh
  useEffect(() => {
    refetch();
    const interval = setInterval(refetch, APP_CONFIG.REFRESH_INTERVAL);
    return () => clearInterval(interval);
  }, [refetch]);

  // Deposit BTC
  const deposit = useCallback(
    async (amount: bigint): Promise<string | null> => {
      if (!account) throw new Error('Wallet not connected');
      setTxLoading(true);
      try {
        const amountU256 = uint256.bnToUint256(amount);
        const result = await account.execute([
          {
            contractAddress: CONTRACTS.VAULT_MANAGER,
            entrypoint: 'deposit',
            calldata: CallData.compile({ amount: amountU256 }),
          },
        ]);
        await provider.waitForTransaction(result.transaction_hash);
        await new Promise(r => setTimeout(r, 2000));
        await refetch();
        return result.transaction_hash;
      } finally {
        setTxLoading(false);
      }
    },
    [account, provider, refetch]
  );

  // Withdraw shares
  const withdraw = useCallback(
    async (shares: bigint): Promise<string | null> => {
      if (!account) throw new Error('Wallet not connected');
      setTxLoading(true);
      try {
        const sharesU256 = uint256.bnToUint256(shares);
        const result = await account.execute([
          {
            contractAddress: CONTRACTS.VAULT_MANAGER,
            entrypoint: 'withdraw',
            calldata: CallData.compile({ shares: sharesU256 }),
          },
        ]);
        await provider.waitForTransaction(result.transaction_hash);
        await new Promise(r => setTimeout(r, 2000));
        await refetch();
        return result.transaction_hash;
      } finally {
        setTxLoading(false);
      }
    },
    [account, provider, refetch]
  );

  return {
    ...data,
    isLoading,
    txLoading,
    deposit,
    withdraw,
    refetch,
  };
}
