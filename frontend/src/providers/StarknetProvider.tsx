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

// Cartridge.gg public RPC (BlastAPI shut down Mar 2026)
const rpc = () => ({ nodeUrl: 'https://api.cartridge.gg/x/starknet/sepolia' });

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
