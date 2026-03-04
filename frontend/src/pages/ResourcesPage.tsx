import { useState, useEffect } from 'react';
import './ResourcesPage.css';

const ChevronIcon = ({ open }: { open: boolean }) => (
  <svg
    viewBox="0 0 24 24"
    stroke="currentColor"
    fill="none"
    strokeWidth="2"
    className={`docs-chevron ${open ? 'open' : ''}`}
  >
    <path d="M9 5l7 7-7 7" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

/* ===== DOCS DATA ===== */
interface DocContent {
  title: string;
  body?: string;
  subsections?: { title: string; items: string[] }[];
  table?: { label: string; value: string }[];
}

interface DocItem {
  id: string;
  label: string;
  category?: string;
  content?: DocContent;
  children?: DocItem[];
}

const docsTree: DocItem[] = [
  {
    id: 'getting-started',
    label: 'Getting Started',
    category: 'Protocol',
    content: {
      title: 'Getting Started',
      body: 'StarkYield is an IL-free Bitcoin yield protocol on Starknet L2. Deposit wBTC into the Vault, receive syBTC shares, and let the protocol generate yield through a leveraged AMM engine with autonomous rebalancing. No manual management, no impermanent loss.',
      subsections: [
        {
          title: 'Prerequisites',
          items: [
            'A Starknet wallet (ArgentX or Braavos browser extension)',
            'wBTC tokens on Starknet Sepolia testnet',
            'ETH on Starknet for gas fees',
            'Minimum deposit: 0.001 BTC',
          ],
        },
      ],
    },
  },
  {
    id: 'how-it-works',
    label: 'How It Works',
    category: 'Protocol',
    children: [
      {
        id: 'connect-wallet',
        label: '1. Connect Wallet',
        content: {
          title: 'Connect Your Starknet Wallet',
          body: 'Connect your ArgentX or Braavos wallet to StarkYield. The protocol operates entirely on Starknet L2, giving you 50 to 100x lower gas fees compared to Ethereum mainnet.',
          subsections: [
            {
              title: 'Supported Wallets',
              items: [
                'ArgentX is the most popular Starknet wallet, available as a browser extension',
                'Braavos is a security-focused Starknet wallet with hardware signer support',
              ],
            },
          ],
        },
      },
      {
        id: 'deposit',
        label: '2. Deposit BTC',
        content: {
          title: 'Deposit wBTC into the Vault',
          body: 'Approve and deposit your wBTC into the StarkYield Vault Manager contract. Your deposit is minted as syBTC vault shares representing your stake in the protocol. The share price appreciates over time as the LEVAMM engine generates yield.',
          subsections: [
            {
              title: 'Deposit Details',
              items: [
                'Minimum deposit: 0.001 BTC (18 decimals on Starknet MockWBTC)',
                'Maximum deposit: 100 BTC per transaction',
                'Requires a prior ERC20 approve() transaction for wBTC',
                'Deposits are tracked on-chain via vault share minting',
                'Share price appreciates as the LEVAMM accrues interest and the VirtualPool distributes profits',
              ],
            },
          ],
        },
      },
      {
        id: 'yield-generation',
        label: '3. Yield Generation',
        content: {
          title: 'Leveraged AMM Yield Engine',
          body: 'Once deposited, your BTC enters the LEVAMM (Leveraged AMM) engine. The protocol manages leveraged positions on concentrated liquidity pools, amplifying returns while controlling risk through autonomous rebalancing.',
          subsections: [
            {
              title: 'LEVAMM Engine',
              items: [
                'The LEVAMM contract opens leveraged positions on concentrated liquidity pools to amplify yield',
                'It tracks the debt-to-value (DTV) ratio in real time to ensure positions stay within safe thresholds',
                'Swap functionality allows the protocol to rebalance between BTC and USDC as market conditions change',
                'Interest accrues automatically on leveraged positions, flowing back to vault shareholders',
              ],
            },
            {
              title: 'Autonomous Rebalancing',
              items: [
                'The VirtualPool contract monitors all positions for leverage drift',
                'When a position becomes over-levered or under-levered, the VirtualPool triggers an on-chain rebalance',
                'Rebalancing is fully autonomous and permissionless. Anyone can call it when conditions are met',
                'Profits from rebalancing are distributed to the vault, increasing the share price for all depositors',
              ],
            },
          ],
        },
      },
      {
        id: 'staking',
        label: '4. Stake syBTC',
        content: {
          title: 'Stake Your Vault Shares',
          body: 'Stake your syBTC shares in the Staker contract to earn additional protocol rewards on top of the base vault yield. This is optional but compounds your returns.',
          subsections: [
            {
              title: 'Staking Details',
              items: [
                'Stake any amount of syBTC shares to earn extra protocol rewards',
                'Rewards accumulate per block and can be claimed at any time',
                'Unstake your shares at any time with no lock-up period',
                'Your staked shares continue earning base vault yield while also earning staking rewards',
              ],
            },
          ],
        },
      },
      {
        id: 'withdraw',
        label: '5. Withdraw',
        content: {
          title: 'Withdraw Your BTC + Yield',
          body: 'Burn your syBTC vault shares at any time to receive your original deposit plus all accumulated yield. The vault redeems at the current share price which increases over time as the LEVAMM generates returns.',
          subsections: [
            {
              title: 'Withdrawal Details',
              items: [
                'No lock-up period. Withdraw at any time',
                'Minimum withdrawal: 0.001 BTC',
                'Share redemption at current share price (principal + yield)',
                'If you have staked shares, unstake first then withdraw',
                'Gas fees paid in ETH on Starknet',
              ],
            },
          ],
        },
      },
    ],
  },
  {
    id: 'architecture',
    label: 'Architecture',
    category: 'Technical',
    content: {
      title: 'Architecture',
      body: 'StarkYield v6 is built on a modular contract architecture deployed on Starknet L2. The system consists of five core contracts that work together: a Factory for deployment, a Vault Manager for deposits and withdrawals, a LEVAMM for leveraged yield generation, a VirtualPool for autonomous rebalancing, and a Staker for additional rewards.',
      table: [
        { label: 'Smart Contracts', value: 'Cairo 2.x on Starknet Sepolia' },
        { label: 'Factory', value: 'Deploys and configures all protocol contracts in a single transaction' },
        { label: 'Vault Manager', value: 'Handles user deposits and withdrawals. Mints/burns syBTC shares. Tracks share price and total assets' },
        { label: 'LEVAMM', value: 'Leveraged AMM engine. Manages leveraged positions on concentrated liquidity pools. Tracks DTV ratio, collateral, and debt' },
        { label: 'VirtualPool', value: 'Autonomous rebalancing engine. Monitors leverage drift and triggers on-chain corrections. Distributes profits to the vault' },
        { label: 'Staker', value: 'Optional staking contract. Users stake syBTC to earn additional protocol rewards' },
        { label: 'Frontend', value: 'React 19, Vite 7, @starknet-react/core, starknet.js, Tailwind CSS' },
        { label: 'Explorer', value: 'Voyager (sepolia.voyager.online)' },
      ],
    },
  },
  {
    id: 'smart-contract',
    label: 'Smart Contracts',
    category: 'Technical',
    content: {
      title: 'Smart Contract Interfaces',
      body: 'StarkYield v6 exposes the following entry points across its core contracts:',
      subsections: [
        {
          title: 'Vault Manager',
          items: [
            'deposit(amount): Deposit wBTC and receive syBTC shares at the current share price',
            'withdraw(shares): Burn syBTC shares and receive wBTC plus accrued yield',
            'rebalance(): Trigger a vault-level rebalance across strategies',
            'get_share_price(): Returns the current syBTC share price in wBTC (view)',
            'get_user_shares(addr): Returns shares held by a given address (view)',
            'get_total_assets(): Returns total wBTC managed by the vault (view)',
          ],
        },
        {
          title: 'LEVAMM',
          items: [
            'swap(direction, amount): Execute a swap between BTC and USDC on the leveraged pool',
            'accrue_interest(): Accrue interest on leveraged positions',
            'get_dtv(): Returns the current debt-to-value ratio (view)',
            'get_collateral_value(): Returns total collateral value (view)',
            'get_debt(): Returns total debt (view)',
            'is_over_levered() / is_under_levered(): Check leverage status (view)',
            'get_current_btc_price(): Returns BTC price from the oracle (view)',
          ],
        },
        {
          title: 'VirtualPool',
          items: [
            'rebalance(): Execute a rebalance when conditions are met. Permissionless',
            'can_rebalance(): Check if a rebalance is currently possible (view)',
            'get_imbalance_direction(): Returns whether the pool is over or under levered (view)',
            'get_total_profit_distributed(): Returns total profit distributed to the vault (view)',
          ],
        },
        {
          title: 'Staker',
          items: [
            'stake(amount): Stake syBTC shares to earn rewards',
            'unstake(amount): Unstake syBTC shares',
            'claim_rewards(): Claim accumulated staking rewards',
            'get_staked_balance(addr): Returns staked balance for a given address (view)',
            'pending_rewards(addr): Returns unclaimed rewards for a given address (view)',
            'get_total_staked(): Returns total syBTC staked across all users (view)',
          ],
        },
      ],
    },
  },
  {
    id: 'network-config',
    label: 'Network Configuration',
    category: 'Reference',
    content: {
      title: 'Network Configuration',
      table: [
        { label: 'Chain', value: 'Starknet Sepolia Testnet (Chain ID: SN_SEPOLIA)' },
        { label: 'RPC URL', value: 'https://api.cartridge.gg/x/starknet/sepolia' },
        { label: 'Vault Manager', value: '0x040489e90e3cafad2446fecb229bc06fea17f535788135469f12a15b983ef976' },
        { label: 'syBTC Token', value: '0x076cb4dadb2db9a95072ecffbb67a61076e642eced3d7f37361ff6f202018be3' },
        { label: 'Factory', value: '0x0253d30100bd7cbbc2bf146bdddcbb4adfc0cae0dc3d2a3ab172a1b4e21c8780' },
        { label: 'LEVAMM', value: '0x0623647a3e0f7f7a7aa0061a692c4e64e916dd853e0d71624da95f4076fff4af' },
        { label: 'VirtualPool', value: '0x00f720c999fdedd3d4a1e393dda0ce1a4e5b0bf079a8608d61f19ba5e77a190c' },
        { label: 'Staker', value: '0x04620f57ef40e7e2293ca6d06153930697bcb88d173f1634ba5cff768acec273' },
        { label: 'MockWBTC', value: '0x066cd5e247ef08479917e46a387057706aeb57cfc5bfa27b225352b304424163' },
        { label: 'Block Explorer', value: 'sepolia.voyager.online' },
        { label: 'Testnet Faucet', value: 'Use the in-app faucet button to mint 1 MockWBTC' },
      ],
    },
  },
  {
    id: 'health-factor',
    label: 'Health Factor',
    category: 'Reference',
    content: {
      title: 'Health Factor',
      body: 'The Health Factor measures the safety of the LEVAMM leveraged positions. It is defined as collateral value divided by debt value. A Health Factor below 1.0 means positions are at risk of liquidation. The VirtualPool automatically rebalances to maintain healthy levels.',
      table: [
        { label: 'Safe (≥ 2.0)', value: 'Position is well-collateralized. No action needed.' },
        { label: 'Moderate (1.5 to 2.0)', value: 'Position is healthy but monitor market conditions.' },
        { label: 'Warning (1.2 to 1.5)', value: 'Consider triggering a manual rebalance.' },
        { label: 'Danger (1.0 to 1.2)', value: 'High risk. Rebalance should trigger automatically.' },
        { label: 'Liquidation (< 1.0)', value: 'Position will be automatically liquidated to protect the vault.' },
      ],
    },
  },
  {
    id: 'important-notes',
    label: 'Important Notes',
    category: 'Reference',
    content: {
      title: 'Important Notes',
      subsections: [
        {
          title: 'Risks & Warnings',
          items: [
            'Starknet Sepolia is a testnet. Contracts and funds have no real value.',
            'Smart contracts are unaudited. Do not deposit significant mainnet funds.',
            'Leveraged positions carry inherent risk during extreme market volatility.',
            'The LEVAMM debt-to-value ratio can spike during flash crashes before rebalancing kicks in.',
            'Always verify contract addresses on Voyager before interacting.',
          ],
        },
        {
          title: 'Technical Notes',
          items: [
            'MockWBTC uses 18 decimals on Starknet Sepolia (not 8 like real BTC).',
            'USDC uses 6 decimals. Always confirm token decimals before crafting calldata.',
            'Starknet transactions use felt252 for addresses. Verify checksum format.',
            'Gas costs are paid in ETH on Starknet.',
            'The VirtualPool rebalance is permissionless. Anyone can trigger it when conditions are met.',
          ],
        },
      ],
    },
  },
];

/* ===== SIDEBAR NAV ITEM ===== */
function SidebarItem({
  item,
  activeId,
  onSelect,
  depth = 0,
}: {
  item: DocItem;
  activeId: string;
  onSelect: (id: string) => void;
  depth?: number;
}) {
  const [open, setOpen] = useState(false);
  const hasChildren = item.children && item.children.length > 0;
  const isActive = item.id === activeId;
  const hasActiveChild =
    hasChildren &&
    item.children!.some(
      (c) =>
        c.id === activeId ||
        (c.children && c.children.some((cc) => cc.id === activeId))
    );

  useEffect(() => {
    if (hasActiveChild) setOpen(true);
  }, [hasActiveChild]);

  if (hasChildren) {
    return (
      <li>
        <button
          className={`docs-sidebar-btn ${hasActiveChild ? 'has-active' : ''}`}
          onClick={() => setOpen((o) => !o)}
          style={{ paddingLeft: `${12 + depth * 16}px` }}
        >
          <span>{item.label}</span>
          <ChevronIcon open={open} />
        </button>
        {open && (
          <ul className="docs-sidebar-children">
            {item.children!.map((child) => (
              <SidebarItem
                key={child.id}
                item={child}
                activeId={activeId}
                onSelect={onSelect}
                depth={depth + 1}
              />
            ))}
          </ul>
        )}
      </li>
    );
  }

  return (
    <li>
      <button
        className={`docs-sidebar-link ${isActive ? 'active' : ''}`}
        onClick={() => onSelect(item.id)}
        style={{ paddingLeft: `${12 + depth * 16}px` }}
      >
        {item.label}
      </button>
    </li>
  );
}

/* ===== CONTENT RENDERER ===== */
function DocContent({ content }: { content: DocContent | undefined }) {
  if (!content) return null;

  return (
    <div className="docs-content">
      <h1 className="docs-content-title">{content.title}</h1>

      {content.body && <p className="docs-content-body">{content.body}</p>}

      {content.subsections &&
        content.subsections.map((sub, i) => (
          <div key={i} className="docs-subsection">
            <h3 className="docs-subsection-title">{sub.title}</h3>
            {sub.items && (
              <ul className="docs-subsection-list">
                {sub.items.map((item, j) => (
                  <li key={j} className="docs-subsection-item">
                    {item}
                  </li>
                ))}
              </ul>
            )}
          </div>
        ))}

      {content.table && (
        <div className="docs-table">
          {content.table.map((row, i) => (
            <div key={i} className="docs-table-row">
              <span className="docs-table-label">{row.label}</span>
              <span className="docs-table-value">{row.value}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/* ===== FIND CONTENT BY ID ===== */
function findContent(tree: DocItem[], id: string): DocContent | undefined {
  for (const item of tree) {
    if (item.id === id) return item.content;
    if (item.children) {
      const found = findContent(item.children, id);
      if (found) return found;
    }
  }
  return undefined;
}

/* ===== MAIN PAGE ===== */
interface ResourcesPageProps {
  onNavigateHome?: () => void;
}

export default function ResourcesPage({ onNavigateHome: _onNavigateHome }: ResourcesPageProps) {
  const [activeId, setActiveId] = useState('getting-started');
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const content = findContent(docsTree, activeId);

  const handleSelect = (id: string) => {
    setActiveId(id);
    setSidebarOpen(false);
  };

  const categories: Record<string, DocItem[]> = {};
  docsTree.forEach((item) => {
    const cat = item.category || 'General';
    if (!categories[cat]) categories[cat] = [];
    categories[cat].push(item);
  });

  return (
    <div className="docs-page">
      {/* Mobile sidebar toggle */}
      <button
        className="docs-mobile-toggle"
        onClick={() => setSidebarOpen((o) => !o)}
      >
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <path d="M4 6h16M4 12h16M4 18h16" strokeLinecap="round" />
        </svg>
        Documentation
      </button>

      {/* Sidebar */}
      <aside className={`docs-sidebar ${sidebarOpen ? 'open' : ''}`}>
        <div className="docs-sidebar-header">
          <span className="docs-sidebar-title">Documentation</span>
        </div>
        <nav className="docs-sidebar-nav">
          {Object.entries(categories).map(([category, items]) => (
            <div key={category} className="docs-sidebar-category">
              <span className="docs-sidebar-category-label">{category}</span>
              <ul className="docs-sidebar-list">
                {items.map((item) => (
                  <SidebarItem
                    key={item.id}
                    item={item}
                    activeId={activeId}
                    onSelect={handleSelect}
                  />
                ))}
              </ul>
            </div>
          ))}
        </nav>

      </aside>

      {/* Mobile overlay */}
      {sidebarOpen && (
        <div
          className="docs-sidebar-overlay"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      {/* Main content */}
      <main className="docs-main">
        <DocContent content={content} />
      </main>
    </div>
  );
}
