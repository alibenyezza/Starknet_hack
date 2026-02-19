import { useState, useEffect, useCallback } from 'react';
import { useAccount } from '@starknet-react/core';
import { RpcProvider, uint256, CallData, hash } from 'starknet';
import { CONTRACTS, NETWORK, APP_CONFIG } from '@/config/constants';

function parseU256Result(result: string[]): bigint {
  if (!result || result.length < 2) return 0n;
  return uint256.uint256ToBN({ low: result[0], high: result[1] });
}

export function useERC20() {
  const { account, address } = useAccount();
  const [balance, setBalance] = useState<bigint>(0n);
  const [allowance, setAllowance] = useState<bigint>(0n);
  const [syBtcBalance, setSyBtcBalance] = useState<bigint>(0n);
  const [isLoading, setIsLoading] = useState(false);
  const [txLoading, setTxLoading] = useState(false);

  const provider = new RpcProvider({ nodeUrl: NETWORK.RPC_URL });

  // Use raw callContract instead of Contract.call to avoid ABI parsing issues
  const callView = useCallback(
    async (contractAddr: string, fnName: string, calldata: string[] = []): Promise<string[]> => {
      try {
        const result = await provider.callContract(
          { contractAddress: contractAddr, entrypoint: fnName, calldata },
          'latest'
        );
        return result;
      } catch {
        return [];
      }
    },
    []
  );

  // Fetch balances and allowance
  const refetch = useCallback(async () => {
    if (!address) return;
    try {
      setIsLoading(true);

      const [balResult, allowResult, syBalResult] = await Promise.all([
        callView(CONTRACTS.BTC_TOKEN, 'balance_of', [address]),
        callView(CONTRACTS.BTC_TOKEN, 'allowance', [address, CONTRACTS.VAULT_MANAGER]),
        callView(CONTRACTS.SY_BTC_TOKEN, 'balance_of', [address]),
      ]);

      console.log('ERC20 raw balance result:', balResult);

      setBalance(parseU256Result(balResult));
      setAllowance(parseU256Result(allowResult));
      setSyBtcBalance(parseU256Result(syBalResult));
    } catch (err) {
      console.error('Failed to fetch ERC20 data:', err);
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

  // Approve vault to spend BTC
  const approve = useCallback(
    async (amount: bigint): Promise<string | null> => {
      if (!account) throw new Error('Wallet not connected');
      setTxLoading(true);
      try {
        const amountU256 = uint256.bnToUint256(amount);
        const result = await account.execute([
          {
            contractAddress: CONTRACTS.BTC_TOKEN,
            entrypoint: 'approve',
            calldata: CallData.compile({
              spender: CONTRACTS.VAULT_MANAGER,
              amount: amountU256,
            }),
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
    balance,
    allowance,
    syBtcBalance,
    isLoading,
    txLoading,
    approve,
    refetch,
  };
}
