import { ReactNode } from 'react';
import { StarknetConfig, publicProvider, InjectedConnector } from '@starknet-react/core';
import { mainnet, sepolia } from '@starknet-react/chains';

interface StarknetProviderProps {
  children: ReactNode;
}

const connectors = [
  new InjectedConnector({ options: { id: 'argentX', name: 'Argent X' } }),
  new InjectedConnector({ options: { id: 'braavos', name: 'Braavos' } }),
];

export function StarknetProvider({ children }: StarknetProviderProps) {
  return (
    <StarknetConfig
      chains={[sepolia, mainnet]}
      provider={publicProvider()}
      connectors={connectors}
      autoConnect
    >
      {children}
    </StarknetConfig>
  );
}
