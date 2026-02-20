import { useState, useRef, useEffect } from 'react';
import { useAccount } from '@starknet-react/core';
import { StaggeredMenu } from '@/components/layout/StaggeredMenu';
import { Hero } from '@/components/landing/Hero';
import ResourcesPage from '@/pages/ResourcesPage';
import TeamPage from '@/pages/TeamPage';
import VaultPage from '@/pages/VaultPage';
import { ToastContainer } from '@/components/ui/Toast';
import { useToast } from '@/hooks/useToast';
import LogoLoop from '@/components/ui/LogoLoop';
import LoadingScreen from '@/components/ui/LoadingScreen';
import { WalletModal } from '@/components/wallet/WalletModal';
import { AccountMenu } from '@/components/wallet/AccountMenu';
import { useBTCPrice } from '@/hooks/useBTCPrice';
import { FileTextIcon } from '@/components/ui/icons/FileTextIcon';
import { HomeIcon } from '@/components/ui/icons/HomeIcon';
import { UserIcon } from '@/components/ui/icons/UserIcon';
import StarBorder from '@/components/ui/StarBorder';
import clsx from 'clsx';

// Import local logo files
import cairoLogo from '@/assets/Cairo_logo_500x500.svg';
import starknetLogo from '@/assets/SN-Stacked-Gradient - On dark bg.svg';
import vesuLogo from '@/assets/vesu logo 1.svg';
import starkLogo from '@/assets/logo stark vf.svg';

type Page = 'home' | 'vault' | 'docs' | 'team';

const partnerLogos = [
  {
    src: 'https://app.ekubo.org/logo.svg',
    alt: 'Ekubo DEX',
    title: 'Ekubo DEX',
    href: 'https://app.ekubo.org',
  },
  {
    src: vesuLogo,
    alt: 'Vesu Lending',
    title: 'Vesu Lending',
    href: 'https://vesu.xyz',
  },
  {
    src: starknetLogo,
    alt: 'Starknet',
    title: 'Starknet',
    href: 'https://www.starknet.io',
  },
  {
    src: cairoLogo,
    alt: 'Cairo Lang',
    title: 'Cairo Lang',
    href: 'https://www.cairo-lang.org',
  },
];

function App() {
  const { isConnected } = useAccount();
  const { toasts, removeToast } = useToast();
  const [isLoading, setIsLoading] = useState(true);
  const [currentPage, setCurrentPage] = useState<Page>('home');
  const [isWalletModalOpen, setIsWalletModalOpen] = useState(false);

  const { price, priceChange24h } = useBTCPrice();
  const connected = isConnected;

  // Auto-navigate to vault when wallet connects from landing page
  const currentPageRef = useRef<Page>(currentPage);
  currentPageRef.current = currentPage;
  useEffect(() => {
    if (isConnected && currentPageRef.current === 'home') {
      setCurrentPage('vault');
    }
  }, [isConnected]);

  if (isLoading) {
    return <LoadingScreen onComplete={() => setIsLoading(false)} />;
  }

  const menuItems = [
    {
      label: 'Home',
      ariaLabel: 'Go to home page',
      onClick: () => setCurrentPage('home'),
      icon: <HomeIcon size={22} />,
    },
    {
      label: 'Docs',
      ariaLabel: 'Read documentation',
      onClick: () => setCurrentPage('docs'),
      icon: <FileTextIcon size={22} />,
    },
    {
      label: 'Meet the Team',
      ariaLabel: 'Meet the StarkYield team',
      onClick: () => setCurrentPage('team'),
      icon: <UserIcon size={22} />,
    },
  ];

  const socialItems = [
    { label: 'Twitter', link: 'https://x.com/DeVinciBC' },
    { label: 'GitHub', link: 'https://github.com/alibenyezza/Starknet_hack' },
    { label: 'Discord', link: 'https://discord.gg/vp3kXPHp' },
  ];

  const headerRight = (
    <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
      {/* BTC Price */}
      <StarBorder
        as="a"
        color="#4444cc"
        speed="4s"
        thickness={1}
        className="sm-btc-price-star"
        href="https://www.coingecko.com/en/coins/bitcoin"
        target="_blank"
        rel="noopener noreferrer"
        style={{ textDecoration: 'none', cursor: 'pointer' }}
      >
        <span style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', fontSize: '0.8rem' }}>
          <span style={{ color: 'rgba(255,255,255,0.5)', fontWeight: 500 }}>BTC</span>
          <span style={{ color: '#fff', fontWeight: 600 }}>${price.toLocaleString()}</span>
          <span
            className={clsx(
              priceChange24h >= 0 ? 'sm-btc-change-positive' : 'sm-btc-change-negative'
            )}
          >
            {priceChange24h >= 0 ? '+' : ''}
            {priceChange24h.toFixed(2)}%
          </span>
        </span>
      </StarBorder>
      {/* Account or Connect */}
      {connected ? (
        <AccountMenu />
      ) : (
        <StarBorder
          as="button"
          color="#4444cc"
          speed="4s"
          thickness={1}
          onClick={() => setIsWalletModalOpen(true)}
        >
          <span style={{ fontWeight: 600, fontSize: '0.85rem' }}>Connect Wallet</span>
        </StarBorder>
      )}
    </div>
  );

  return (
    <div className="min-h-screen" style={{ position: 'relative', background: 'transparent' }}>
      {/* Fixed StaggeredMenu */}
      <StaggeredMenu
        isFixed
        position="right"
        items={menuItems}
        socialItems={socialItems}
        displaySocials
        displayItemNumbering
        menuButtonColor="#ffffff"
        openMenuButtonColor="#ffffff"
        changeMenuColorOnOpen
        colors={['#272757', '#1a1a44']}
        accentColor="#4444cc"
        logoText="StarkYield"
        logoImage={starkLogo}
        rightContent={headerRight}
        onLogoClick={() => setCurrentPage('home')}
      />

      {/* Main content */}
      <main style={{ position: 'relative', zIndex: 1 }}>
        {currentPage === 'docs' ? (
          <ResourcesPage onNavigateHome={() => setCurrentPage('home')} />
        ) : currentPage === 'team' ? (
          <TeamPage onNavigateHome={() => setCurrentPage('home')} />
        ) : currentPage === 'vault' ? (
          isConnected
            ? <VaultPage onNavigateHome={() => setCurrentPage('home')} />
            : <Hero
                onNavigateDocs={() => setCurrentPage('docs')}
                onNavigateVault={() => setCurrentPage('vault')}
                isConnected={isConnected}
              />
        ) : (
          /* 'home' — always landing, even when connected */
          <Hero
            onNavigateDocs={() => setCurrentPage('docs')}
            onNavigateVault={() => setCurrentPage('vault')}
            isConnected={isConnected}
          />
        )}
      </main>

      {/* Footer — only on landing page */}
      {currentPage === 'home' && (
        <footer
          className="border-t"
          style={{
            borderColor: 'rgba(39, 39, 87, 0.3)',
            position: 'relative',
            zIndex: 2,
            background: '#000',
          }}
        >
          {/* Partner Logos Loop */}
          <div className="py-16" style={{ background: '#000' }}>
            <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
              <h3 className="text-center text-sm font-medium text-gray-400 mb-12 uppercase tracking-wider">
                Built with
              </h3>
              <div
                className="rounded-2xl py-14 px-8"
                style={{
                  background: 'rgba(39, 39, 87, 0.1)',
                  border: '1px solid rgba(39, 39, 87, 0.2)',
                }}
              >
                <LogoLoop
                  logos={partnerLogos}
                  speed={30}
                  direction="left"
                  logoHeight={55}
                  gap={60}
                  pauseOnHover
                  scaleOnHover
                  fadeOut
                  fadeOutColor="#000"
                  ariaLabel="Protocol partners and technologies"
                />
              </div>
            </div>
          </div>

          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
            <div className="flex flex-col md:flex-row items-center justify-between gap-4">
              <div className="flex items-center gap-3">
                <img src={starkLogo} alt="StarkYield" style={{ height: 28, width: 'auto' }} />
                <span className="text-sm text-gray-500">&copy; 2026 StarkYield. Built on Starknet.</span>
              </div>
              <div className="app-footer-socials">
                <a href="https://x.com/DeVinciBC" target="_blank" rel="noreferrer" className="app-footer-social" title="X / Twitter">
                  <svg viewBox="0 0 24 24" fill="currentColor" width="17" height="17"><path d="M13.6823 10.6218L20.2391 3H18.6854L12.9921 9.61788L8.44486 3L3.2002 3L10.0765 13.0074L3.2002 21H4.75404L10.7663 14.0113L15.5685 21H20.8132L13.6819 10.6218H13.6823ZM11.5541 13.0956L10.8574 12.0991L5.31391 4.16971H7.70053L12.1742 10.5689L12.8709 11.5655L18.6861 19.8835H16.2995L11.5541 13.096V13.0956Z" /></svg>
                </a>
                <a href="https://discord.gg/vp3kXPHp" target="_blank" rel="noreferrer" className="app-footer-social" title="Discord">
                  <svg viewBox="0 0 25 24" fill="currentColor" width="18" height="18"><path d="M19.7701 5.33005C18.4401 4.71005 17.0001 4.26005 15.5001 4.00005C15.487 3.99963 15.4739 4.00209 15.4618 4.00728C15.4497 4.01246 15.4389 4.02023 15.4301 4.03005C15.2501 4.36005 15.0401 4.79005 14.9001 5.12005C13.3091 4.88005 11.6911 4.88005 10.1001 5.12005C9.96012 4.78005 9.75012 4.36005 9.56012 4.03005C9.55012 4.01005 9.52012 4.00005 9.49012 4.00005C7.99012 4.26005 6.56012 4.71005 5.22012 5.33005C5.21012 5.33005 5.20012 5.34005 5.19012 5.35005C2.47012 9.42005 1.72012 13.38 2.09012 17.3C2.09012 17.32 2.10012 17.34 2.12012 17.35C3.92012 18.67 5.65012 19.47 7.36012 20C7.39012 20.01 7.42012 20 7.43012 19.98C7.83012 19.43 8.19012 18.85 8.50012 18.24C8.52012 18.2 8.50012 18.16 8.46012 18.15C7.89012 17.93 7.35012 17.67 6.82012 17.37C6.78012 17.35 6.78012 17.29 6.81012 17.26C6.92012 17.18 7.03012 17.09 7.14012 17.01C7.16012 16.99 7.19012 16.99 7.21012 17C10.6501 18.57 14.3601 18.57 17.7601 17C17.7801 16.99 17.8101 16.99 17.8301 17.01C17.9401 17.1 18.0501 17.18 18.1601 17.27C18.2001 17.3 18.2001 17.36 18.1501 17.38C17.6301 17.69 17.0801 17.94 16.5101 18.16C16.4701 18.17 16.4601 18.22 16.4701 18.25C16.7901 18.86 17.1501 19.44 17.5401 19.99C17.5701 20 17.6001 20.01 17.6301 20C19.3501 19.47 21.0801 18.67 22.8801 17.35C22.9001 17.34 22.9101 17.32 22.9101 17.3C23.3501 12.77 22.1801 8.84005 19.8101 5.35005C19.8001 5.34005 19.7901 5.33005 19.7701 5.33005ZM9.02012 14.91C7.99012 14.91 7.13012 13.96 7.13012 12.79C7.13012 11.62 7.97012 10.67 9.02012 10.67C10.0801 10.67 10.9201 11.63 10.9101 12.79C10.9101 13.96 10.0701 14.91 9.02012 14.91ZM15.9901 14.91C14.9601 14.91 14.1001 13.96 14.1001 12.79C14.1001 11.62 14.9401 10.67 15.9901 10.67C17.0501 10.67 17.8901 11.63 17.8801 12.79C17.8801 13.96 17.0501 14.91 15.9901 14.91Z" /></svg>
                </a>
                <a href="https://github.com/alibenyezza/Starknet_hack" target="_blank" rel="noreferrer" className="app-footer-social" title="GitHub">
                  <svg viewBox="0 0 24 24" fill="currentColor" width="18" height="18"><path d="M12 2C6.477 2 2 6.477 2 12c0 4.42 2.865 8.17 6.839 9.49.5.092.682-.217.682-.482 0-.237-.008-.866-.013-1.7-2.782.604-3.369-1.34-3.369-1.34-.454-1.156-1.11-1.464-1.11-1.464-.908-.62.069-.608.069-.608 1.003.07 1.531 1.03 1.531 1.03.892 1.529 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.11-4.555-4.943 0-1.091.39-1.984 1.029-2.683-.103-.253-.446-1.27.098-2.647 0 0 .84-.269 2.75 1.025A9.578 9.578 0 0112 6.836c.85.004 1.705.115 2.504.337 1.909-1.294 2.747-1.025 2.747-1.025.546 1.377.203 2.394.1 2.647.64.699 1.028 1.592 1.028 2.683 0 3.842-2.339 4.687-4.566 4.935.359.309.678.919.678 1.852 0 1.336-.012 2.415-.012 2.743 0 .267.18.578.688.48C19.138 20.167 22 16.418 22 12c0-5.523-4.477-10-10-10z" /></svg>
                </a>
              </div>
            </div>
          </div>
        </footer>
      )}

      {/* Wallet Connection Modal */}
      <WalletModal
        isOpen={isWalletModalOpen}
        onClose={() => setIsWalletModalOpen(false)}
      />

      {/* Toast notifications */}
      <ToastContainer toasts={toasts} removeToast={removeToast} />
    </div>
  );
}

export default App;
