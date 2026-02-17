# StarkYield Frontend

> IL-Free Bitcoin Liquidity Protocol on Starknet

A modern, elegant frontend for StarkYield built with React, TypeScript, and Tailwind CSS.

## Features

- 🎨 Clean, minimalist design inspired by yieldbasis.com
- ⚡ Built on Starknet for low gas fees and high security
- 🔐 ArgentX wallet integration
- 📊 Real-time analytics and performance tracking
- 📱 Fully responsive design
- 🎭 Smooth animations with Framer Motion
- 📈 Interactive charts with Recharts

## Tech Stack

- **Framework**: React 18 + TypeScript
- **Build Tool**: Vite
- **Styling**: Tailwind CSS
- **Blockchain**: Starknet.js + starknet-react
- **Charts**: Recharts
- **Animations**: Framer Motion

## Getting Started

### Prerequisites

- Node.js 18+
- npm or yarn
- ArgentX wallet extension

### Installation

1. Clone the repository:
```bash
cd frontend
```

2. Install dependencies:
```bash
npm install
```

3. Copy the environment file:
```bash
cp .env.example .env
```

4. Update the `.env` file with your contract addresses

5. Start the development server:
```bash
npm run dev
```

The app will be available at `http://localhost:3000`

## Building for Production

```bash
npm run build
```

The production build will be in the `dist` folder.

## Project Structure

```
src/
├── components/
│   ├── ui/              # Reusable UI components
│   ├── layout/          # Layout components (Header, Footer)
│   └── vault/           # Vault-specific components
├── pages/               # Page components
├── hooks/               # Custom React hooks
├── utils/               # Utility functions
├── config/              # Configuration and constants
├── types/               # TypeScript types
├── styles/              # Global styles
└── providers/           # Context providers
```

## Key Components

### UI Components
- `Button` - Customizable button with variants
- `Card` - Container component for content
- `Input` - Form input with validation
- `Badge` - Status indicators
- `Modal` - Dialog component
- `StatCard` - Statistics display card

### Vault Components
- `HealthFactorGauge` - Visual health factor indicator
- `StrategyBreakdown` - Strategy allocation visualization
- `PerformanceChart` - Historical performance chart
- `TransactionHistory` - Recent transaction list
- `DepositModal` - Deposit flow
- `WithdrawModal` - Withdrawal flow

## Custom Hooks

- `useVault()` - Vault state and operations
- `useBTCPrice()` - BTC price data
- `useTransactions()` - Transaction history

## Design System

### Colors

- **Bitcoin Orange**: Primary brand color
- **Success Green**: Positive indicators
- **Warning Yellow**: Moderate risk
- **Danger Red**: High risk

### Typography

- **Font**: Inter (sans-serif)
- **Mono**: JetBrains Mono (code/addresses)

### Spacing

Based on Tailwind's default spacing scale (4px base)

## Smart Contract Integration

Update contract addresses in `src/config/constants.ts`:

```typescript
export const CONTRACTS = {
  VAULT_MANAGER: '0x...',
  SY_BTC_TOKEN: '0x...',
  BTC_TOKEN: '0x...',
  USDC_TOKEN: '0x...',
  // ...
};
```

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see LICENSE file for details

## Support

- Documentation: [docs.starkyield.io](https://docs.starkyield.io)
- Discord: [discord.gg/starkyield](https://discord.gg/starkyield)
- Twitter: [@StarkYield](https://twitter.com/starkyield)
