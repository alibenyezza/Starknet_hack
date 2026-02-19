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
      body: 'StarkYield is an IL-free Bitcoin liquidity protocol on Starknet L2. It allows users to deposit BTC (via wBTC) and automatically deploy it across multiple yield strategies — Ekubo DEX, Vesu lending, and Endur staking — using dynamic leverage rebalancing to eliminate impermanent loss and maximize returns.',
      subsections: [
        {
          title: 'Prerequisites',
          items: [
            'A Starknet wallet (ArgentX or Braavos browser extension)',
            'wBTC or STRK tokens on Starknet (Sepolia testnet or Mainnet)',
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
          body: 'Connect your ArgentX or Braavos wallet to StarkYield. The protocol operates entirely on Starknet L2, giving you 50–100x lower gas fees compared to Ethereum mainnet.',
          subsections: [
            {
              title: 'Supported Wallets',
              items: [
                'ArgentX — Most popular Starknet wallet, available as browser extension',
                'Braavos — Security-focused Starknet wallet with hardware signer support',
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
          body: 'Approve and deposit your wBTC into the StarkYield Vault Manager contract. Your deposit is minted as syBTC vault shares, representing your proportional stake in the yield strategies.',
          subsections: [
            {
              title: 'Deposit Details',
              items: [
                'Minimum deposit: 0.001 BTC (1e5 in raw units, 8 decimals)',
                'Maximum deposit: 100 BTC per transaction',
                'Requires a prior ERC20 approve() transaction for wBTC',
                'Deposits are tracked on-chain via vault share minting',
                'Share price appreciates as yield accrues',
              ],
            },
          ],
        },
      },
      {
        id: 'yield-generation',
        label: '3. Yield Generation',
        content: {
          title: 'Multi-Strategy Yield Generation',
          body: 'Once deposited, your BTC is automatically allocated across three yield strategies by the Vault Manager. The allocation is dynamically rebalanced to optimize risk-adjusted returns.',
          subsections: [
            {
              title: 'Strategy Allocation',
              items: [
                'Ekubo DEX (35%) — Provide liquidity to BTC/USDC concentrated pools; IL mitigated via leverage rebalancing',
                'Vesu Lending (40%) — Lend wBTC to earn interest from borrowers; lowest risk, stable APY',
                'Endur Staking (25%) — Stake into liquid staking derivatives; earns staking rewards + DeFi yield',
              ],
            },
            {
              title: 'IL Mitigation',
              items: [
                'Real-time monitoring of Ekubo pool price ranges via Pragma Oracle',
                'Automatic leverage adjustment when BTC price deviates from range',
                'Rebalancing triggered on-chain by the Vault Manager via Cairo smart contracts',
              ],
            },
          ],
        },
      },
      {
        id: 'withdraw',
        label: '4. Withdraw',
        content: {
          title: 'Withdraw Your BTC + Yield',
          body: 'Burn your syBTC vault shares at any time to receive your original deposit plus all accumulated yield. The vault redeems at the current share price which increases over time.',
          subsections: [
            {
              title: 'Withdrawal Details',
              items: [
                'No lock-up period — withdraw at any time',
                'Minimum withdrawal: 0.001 BTC',
                'Share redemption at current share price (principal + yield)',
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
      body: 'StarkYield is built entirely on Starknet L2 using Cairo smart contracts. It integrates with Ekubo DEX, Vesu lending, and Endur staking protocols through on-chain interfaces. Pragma Oracle provides real-time BTC/USDC price feeds for IL detection and rebalancing triggers.',
      table: [
        { label: 'Smart Contracts', value: 'Cairo 2.x on Starknet Sepolia / Mainnet' },
        { label: 'Vault Manager', value: 'IVaultManager interface — deposit, withdraw, rebalance, claimYield' },
        { label: 'Oracle', value: 'Pragma Oracle — BTC/USD price feed for rebalancing triggers' },
        { label: 'DEX Integration', value: 'Ekubo DEX — concentrated liquidity BTC/USDC pools' },
        { label: 'Lending Integration', value: 'Vesu Protocol — wBTC lending markets' },
        { label: 'Staking Integration', value: 'Endur — liquid BTC staking derivatives' },
        { label: 'Frontend', value: 'React 18, Vite, @starknet-react/core, Tailwind CSS' },
        { label: 'Explorer', value: 'Starkscan (sepolia.starkscan.co / starkscan.co)' },
      ],
    },
  },
  {
    id: 'smart-contract',
    label: 'Smart Contract',
    category: 'Technical',
    content: {
      title: 'Smart Contract Interface',
      body: 'The StarkYield Vault Manager exposes the following main entry points:',
      table: [
        { label: 'deposit(amount)', value: 'Deposit wBTC. Mints syBTC shares proportional to current share price. Min: 0.001 BTC.' },
        { label: 'withdraw(shares)', value: 'Burn syBTC shares to redeem wBTC + accrued yield at current share price.' },
        { label: 'claimYield()', value: 'Claim accumulated yield without withdrawing principal. Returns wBTC.' },
        { label: 'rebalance()', value: 'Permissioned rebalancing function. Redistributes allocation across Ekubo, Vesu, Endur based on current APY and IL risk.' },
        { label: 'getSharePrice()', value: 'Returns current syBTC share price in wBTC. Increases as yield accrues. (view)' },
        { label: 'getUserPosition(addr)', value: 'Returns shares held, wBTC value, USD value, and earnings for a given address.' },
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
        { label: 'RPC URL', value: 'https://starknet-sepolia.public.blastapi.io' },
        { label: 'Vault Manager', value: '0x0000000000000000000000000000000000000000 (deploy pending)' },
        { label: 'syBTC Token', value: '0x0000000000000000000000000000000000000000 (deploy pending)' },
        { label: 'wBTC Token', value: 'Starknet Sepolia wBTC contract address' },
        { label: 'Ekubo Pool', value: 'BTC/USDC concentrated liquidity pool on Ekubo' },
        { label: 'Vesu Market', value: 'wBTC lending market on Vesu' },
        { label: 'Pragma Oracle', value: 'BTC/USD feed — 0x4254432f555344 (key)' },
        { label: 'Block Explorer', value: 'sepolia.starkscan.co' },
        { label: 'Testnet Faucet', value: 'faucet.starknet.io (request STRK / ETH)' },
      ],
    },
  },
  {
    id: 'health-factor',
    label: 'Health Factor',
    category: 'Reference',
    content: {
      title: 'Health Factor',
      body: 'The Health Factor measures the safety of your leveraged position in the Ekubo DEX strategy. It is defined as collateral value divided by debt value. A Health Factor below 1.0 means your position is at risk of liquidation.',
      table: [
        { label: 'Safe (≥ 2.0)', value: 'Position is well-collateralized. No action needed.' },
        { label: 'Moderate (1.5–2.0)', value: 'Position is healthy but monitor market conditions.' },
        { label: 'Warning (1.2–1.5)', value: 'Consider reducing leverage or adding collateral.' },
        { label: 'Danger (1.0–1.2)', value: 'High risk of liquidation. Immediate action recommended.' },
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
            'Starknet Sepolia is a testnet — contracts and funds have no real value.',
            'Smart contracts are unaudited. Do not deposit significant mainnet funds.',
            'The Ekubo liquidity strategy carries residual impermanent loss risk during extreme market moves.',
            'Vesu lending positions can be liquidated if the BTC/USDC price drops sharply.',
            'Endur staking derivatives may have unlock delays depending on the underlying protocol.',
            'Always verify contract addresses on Starkscan before interacting.',
          ],
        },
        {
          title: 'Technical Notes',
          items: [
            'wBTC uses 8 decimals on Starknet. 0.001 BTC = 100,000 in raw units.',
            'USDC uses 6 decimals. Always confirm token decimals before crafting calldata.',
            'Starknet transactions use felt252 for addresses — verify checksum format.',
            'Gas costs are paid in ETH on Starknet (not STRK on Sepolia).',
            'The Pragma Oracle BTC/USD feed key is 0x4254432f555344 (hex-encoded "BTC/USD").',
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

export default function ResourcesPage({ onNavigateHome }: ResourcesPageProps) {
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
