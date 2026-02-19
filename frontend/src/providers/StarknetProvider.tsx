import { ReactNode } from 'react';
import { StarknetConfig, jsonRpcProvider, argent, braavos } from '@starknet-react/core';
import { sepolia } from '@starknet-react/chains';
import { NETWORK } from '@/config/constants';

interface StarknetProviderProps {
  children: ReactNode;
}

const connectors = [
  braavos(),
  argent(),
];

function rpcProvider() {
  return jsonRpcProvider({
    rpc: () => ({ nodeUrl: NETWORK.RPC_URL }),
  });
}

export function StarknetProvider({ children }: StarknetProviderProps) {
  return (
    <StarknetConfig
      chains={[sepolia]}
      provider={rpcProvider()}
      connectors={connectors}
      autoConnect
    >
      {children}
    </StarknetConfig>
  );
}
