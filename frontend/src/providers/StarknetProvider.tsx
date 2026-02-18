import { ReactNode } from 'react';
import { StarknetConfig, publicProvider, argent, braavos } from '@starknet-react/core';
import { sepolia } from '@starknet-react/chains';

interface StarknetProviderProps {
  children: ReactNode;
}

const connectors = [
  braavos(),
  argent(),
];

export function StarknetProvider({ children }: StarknetProviderProps) {
  return (
    <StarknetConfig
      chains={[sepolia]}
      provider={publicProvider()}
      connectors={connectors}
      autoConnect
    >
      {children}
    </StarknetConfig>
  );
}
