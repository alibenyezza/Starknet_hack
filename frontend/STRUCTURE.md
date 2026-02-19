# Frontend File Structure

```
frontend/
├── public/
│   └── logo.svg                 # App logo
│
├── src/
│   ├── components/
│   │   ├── ui/                  # Base UI components
│   │   │   ├── Badge.tsx
│   │   │   ├── Button.tsx
│   │   │   ├── Card.tsx
│   │   │   ├── Input.tsx
│   │   │   ├── LoadingSpinner.tsx
│   │   │   ├── Modal.tsx
│   │   │   ├── Skeleton.tsx
│   │   │   ├── StatCard.tsx
│   │   │   ├── Toast.tsx
│   │   │   └── index.ts         # Barrel export
│   │   │
│   │   ├── layout/              # Layout components
│   │   │   ├── Header.tsx       # Main header with wallet
│   │   │   └── MobileMenu.tsx   # Mobile navigation
│   │   │
│   │   ├── vault/               # Vault-specific components
│   │   │   ├── DepositModal.tsx
│   │   │   ├── WithdrawModal.tsx
│   │   │   ├── HealthFactorGauge.tsx
│   │   │   ├── StrategyBreakdown.tsx
│   │   │   ├── PerformanceChart.tsx
│   │   │   └── TransactionHistory.tsx
│   │   │
│   │   └── landing/             # Landing page components
│   │       └── Hero.tsx
│   │
│   ├── hooks/                   # Custom React hooks
│   │   ├── useVault.ts          # Vault operations & state
│   │   ├── useBTCPrice.ts       # BTC price data
│   │   ├── useTransactions.ts   # Transaction history
│   │   └── useToast.ts          # Toast notifications
│   │
│   ├── pages/                   # Page components
│   │   └── Dashboard.tsx        # Main dashboard page
│   │
│   ├── providers/               # Context providers
│   │   └── StarknetProvider.tsx # Starknet wallet provider
│   │
│   ├── utils/                   # Utility functions
│   │   ├── format.ts            # Formatting utilities
│   │   └── health-factor.ts     # Health factor utilities
│   │
│   ├── config/                  # Configuration
│   │   └── constants.ts         # App constants & addresses
│   │
│   ├── types/                   # TypeScript types
│   │   └── index.ts             # Type definitions
│   │
│   ├── styles/                  # Global styles
│   │   └── index.css            # Tailwind & custom CSS
│   │
│   ├── App.tsx                  # Root App component
│   └── main.tsx                 # Entry point
│
├── .env.example                 # Environment template
├── .gitignore                   # Git ignore rules
├── index.html                   # HTML template
├── package.json                 # Dependencies
├── postcss.config.js            # PostCSS config
├── README.md                    # Project documentation
├── SETUP.md                     # Setup guide
├── STRUCTURE.md                 # This file
├── tailwind.config.js           # Tailwind configuration
├── tsconfig.json                # TypeScript config
├── tsconfig.node.json           # TypeScript node config
└── vite.config.ts               # Vite configuration
```

## Component Hierarchy

```
App
├── StarknetProvider
│   ├── Header
│   │   ├── Navigation (desktop)
│   │   ├── BTC Price Ticker
│   │   ├── Wallet Button
│   │   └── MobileMenu
│   │
│   ├── Hero (when not connected)
│   │   ├── Stats Cards
│   │   ├── Feature Cards
│   │   └── How It Works
│   │
│   └── Dashboard (when connected)
│       ├── Stats Grid
│       │   └── StatCard × 4
│       │
│       ├── Left Column
│       │   ├── PerformanceChart
│       │   ├── StrategyBreakdown
│       │   └── TransactionHistory
│       │
│       └── Right Column
│           ├── HealthFactorGauge
│           └── Quick Actions Card
│
└── ToastContainer
    └── Toast × N
```

## Data Flow

```
User Action
    ↓
Component Event Handler
    ↓
Custom Hook (useVault, etc.)
    ↓
Starknet Contract Call
    ↓
Update Local State
    ↓
Re-render Components
    ↓
Show Toast Notification
```

## State Management

### Local Component State
- Modal open/closed
- Form inputs
- UI toggles

### Custom Hook State
- Vault statistics
- User position
- Transaction history
- BTC price

### Starknet React State
- Wallet connection
- Account address
- Network info

## Styling Strategy

### Tailwind Classes
- Utility-first approach
- Responsive modifiers (sm:, md:, lg:)
- Custom utilities via @layer

### Custom CSS
- Minimal custom CSS
- Animations and keyframes
- CSS variables for theming

### Component Styles
- Inline Tailwind classes
- clsx for conditional classes
- No CSS modules or styled-components

## Best Practices

### Components
- Single Responsibility Principle
- Props interface for TypeScript
- Default exports for pages, named for components
- Composition over inheritance

### Hooks
- Prefix with 'use'
- Return object with clear property names
- Handle loading and error states
- Clean up effects properly

### Performance
- Lazy load heavy components
- Memoize expensive calculations
- Optimize re-renders with React.memo
- Use virtualization for long lists

### Accessibility
- Semantic HTML elements
- ARIA labels where needed
- Keyboard navigation support
- Focus management in modals

## Adding New Features

### New Page
1. Create in `src/pages/`
2. Add route (if using router)
3. Import in App.tsx
4. Update navigation

### New Component
1. Create in appropriate folder
2. Define TypeScript interface
3. Add to index.ts (if in ui/)
4. Document props

### New Hook
1. Create in `src/hooks/`
2. Follow naming convention (useXxx)
3. Add TypeScript types
4. Document return values

### New Utility
1. Add to `src/utils/`
2. Export functions
3. Add JSDoc comments
4. Write unit tests (optional)
