# StarkYield Frontend - Setup Guide

## Quick Start

### 1. Install Dependencies

```bash
cd frontend
npm install
```

### 2. Configure Environment

```bash
cp .env.example .env
```

Edit `.env` and update contract addresses when available.

### 3. Start Development Server

```bash
npm run dev
```

Visit `http://localhost:3000`

## Available Scripts

- `npm run dev` - Start development server
- `npm run build` - Build for production
- `npm run preview` - Preview production build
- `npm run lint` - Run ESLint

## Project Architecture

### Component Structure

```
components/
├── ui/              # Base UI components (Button, Card, Input, etc.)
├── layout/          # Layout components (Header, Footer, MobileMenu)
├── vault/           # Vault-specific components
└── landing/         # Landing page components
```

### Key Features

1. **Wallet Integration**
   - ArgentX wallet support via starknet-react
   - Auto-connect on page load
   - Wallet state management

2. **Vault Operations**
   - Deposit BTC
   - Withdraw BTC
   - View position & earnings
   - Real-time health factor monitoring

3. **Analytics**
   - Performance charts (TVL, APY)
   - Strategy breakdown visualization
   - Transaction history

4. **Responsive Design**
   - Mobile-first approach
   - Tablet & desktop optimized
   - Touch-friendly interactions

## Custom Hooks

### useVault()
Manages vault state and operations:
```typescript
const {
  vaultStats,         // Total vault statistics
  userPosition,       // User's position details
  strategyAllocation, // Strategy breakdown
  healthFactor,       // Health factor data
  deposit,            // Deposit function
  withdraw,           // Withdraw function
  claimYield,         // Claim yield function
} = useVault();
```

### useBTCPrice()
Fetches current BTC price:
```typescript
const {
  price,           // Current BTC price
  priceChange24h,  // 24h price change %
  refresh,         // Manual refresh function
} = useBTCPrice();
```

### useTransactions()
Fetches user transaction history:
```typescript
const {
  transactions,  // Array of transactions
  isLoading,     // Loading state
  refresh,       // Refresh transactions
} = useTransactions();
```

### useToast()
Display toast notifications:
```typescript
const {
  success,  // Show success toast
  error,    // Show error toast
  info,     // Show info toast
  warning,  // Show warning toast
} = useToast();

// Usage
toast.success('Deposit successful!');
toast.error('Transaction failed');
```

## Styling

### Tailwind Utilities

Custom utilities available:
- `.gradient-text` - Bitcoin gradient text
- `.card` - Standard card style
- `.btn-primary` - Primary button
- `.btn-secondary` - Secondary button
- `.btn-outline` - Outline button
- `.input` - Standard input

### Colors

```css
bitcoin-*    /* Orange shades (primary brand) */
success-*    /* Green shades (positive) */
warning-*    /* Yellow shades (moderate risk) */
danger-*     /* Red shades (high risk) */
```

### Animations

```css
animate-fade-in      /* Fade in */
animate-slide-up     /* Slide up */
animate-slide-down   /* Slide down */
animate-scale-in     /* Scale in */
animate-shimmer      /* Loading shimmer */
animate-pulse-soft   /* Soft pulse */
```

## Smart Contract Integration

### Update Contract Addresses

Edit `src/config/constants.ts`:

```typescript
export const CONTRACTS = {
  VAULT_MANAGER: '0xYourVaultAddress',
  SY_BTC_TOKEN: '0xYourTokenAddress',
  BTC_TOKEN: '0xBTCAddress',
  USDC_TOKEN: '0xUSDCAddress',
  // ...
};
```

### Add Contract ABI

1. Place compiled ABI in `src/abis/`
2. Import in hooks:

```typescript
import VAULT_ABI from '@/abis/vault.json';

const { contract } = useContract({
  address: CONTRACTS.VAULT_MANAGER,
  abi: VAULT_ABI,
});
```

## Testing

### Manual Testing Checklist

- [ ] Wallet connection (ArgentX, Braavos)
- [ ] Deposit flow (input validation, transaction)
- [ ] Withdraw flow (percentage slider, confirmation)
- [ ] Charts rendering (all timeframes)
- [ ] Responsive design (mobile, tablet, desktop)
- [ ] Toast notifications
- [ ] Health factor gauge accuracy
- [ ] Transaction history display

## Deployment

### Build for Production

```bash
npm run build
```

Output: `dist/` folder

### Deploy to Vercel

```bash
npm install -g vercel
vercel
```

### Deploy to Netlify

```bash
npm install -g netlify-cli
netlify deploy --prod
```

## Common Issues

### Issue: Wallet not connecting

**Solution**:
- Ensure ArgentX extension is installed
- Check network matches (testnet/mainnet)
- Clear browser cache

### Issue: Contract call failing

**Solution**:
- Verify contract addresses in `.env`
- Check wallet has sufficient balance
- Ensure correct network (Sepolia testnet)

### Issue: Charts not rendering

**Solution**:
- Check Recharts is installed: `npm install recharts`
- Verify data format matches chart expectations

## Performance Optimization

### Code Splitting

Vite automatically code-splits. For manual splitting:

```typescript
const Dashboard = lazy(() => import('@/pages/Dashboard'));
```

### Image Optimization

Use modern formats (WebP) and lazy loading:

```tsx
<img loading="lazy" src="image.webp" alt="..." />
```

## Support

- **Documentation**: `/docs`
- **Discord**: [Join our Discord](#)
- **GitHub Issues**: [Report issues](#)

## License

MIT - See LICENSE file
