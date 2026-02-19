// MockWBTC ABI - faucet function for testnet
export const MOCK_WBTC_ABI = [
  {
    type: 'impl',
    name: 'MockWBTCImpl',
    interface_name: 'starkyield::vault::mock_wbtc::IMockWBTC',
  },
  {
    type: 'struct',
    name: 'core::integer::u256',
    members: [
      { name: 'low', type: 'core::integer::u128' },
      { name: 'high', type: 'core::integer::u128' },
    ],
  },
  {
    type: 'interface',
    name: 'starkyield::vault::mock_wbtc::IMockWBTC',
    items: [
      {
        type: 'function',
        name: 'faucet',
        inputs: [{ name: 'amount', type: 'core::integer::u256' }],
        outputs: [],
        state_mutability: 'external',
      },
    ],
  },
] as const;
