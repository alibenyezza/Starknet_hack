import { ReactNode } from 'react';
import { StarknetConfig, jsonRpcProvider, argent, braavos } from '@starknet-react/core';
import { sepolia } from '@starknet-react/chains';

interface StarknetProviderProps {
  children: ReactNode;
}

const connectors = [
  braavos(),
  argent(),
];

// /rpc is proxied by Vite to BlastAPI (avoids CORS in development)
const rpc = () => ({ nodeUrl: '/rpc' });

export function StarknetProvider({ children }: StarknetProviderProps) {
  return (
    <StarknetConfig
      chains={[sepolia]}
      provider={jsonRpcProvider({ rpc })}
      connectors={connectors}
      autoConnect
    >
      {children}
    </StarknetConfig>
  );
}
