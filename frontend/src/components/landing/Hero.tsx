import { useState } from 'react';
import StarBorder from '@/components/ui/StarBorder';
import { WalletModal } from '@/components/wallet/WalletModal';
import FeaturesSection from './FeaturesSection';
import heroVideo from '@/assets/video/272517_small.mp4';


interface HeroProps {
  onNavigateDocs?: () => void;
  onNavigateVault?: () => void;
  isConnected?: boolean;
}

export function Hero({ onNavigateDocs: _onNavigateDocs, onNavigateVault, isConnected }: HeroProps) {
  const [isWalletModalOpen, setIsWalletModalOpen] = useState(false);

  const handleCTA = () => {
    if (isConnected) {
      onNavigateVault?.();
    } else {
      setIsWalletModalOpen(true);
    }
  };

  return (
    <div className="relative min-h-screen" style={{ background: 'transparent' }}>

      {/* Video background — fixed, covers full viewport */}
      <div
        style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          width: '100vw',
          height: '100vh',
          zIndex: 0,
          pointerEvents: 'none',
          overflow: 'hidden',
        }}
      >
        <video
          autoPlay
          loop
          muted
          playsInline
          style={{
            width: '100%',
            height: '100%',
            objectFit: 'cover',
          }}
        >
          <source src={heroVideo} type="video/mp4" />
        </video>
        {/* Dark overlay */}
        <div
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundColor: 'rgba(0, 0, 0, 0.55)',
          }}
        />
      </div>

      {/* Hero content */}
      <div
        style={{
          position: 'relative',
          zIndex: 1,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          textAlign: 'center',
          minHeight: '100vh',
          padding: 'clamp(6rem, 12vw, 9rem) clamp(1rem, 4vw, 2rem) 4rem',
        }}
      >
        {/* Title */}
        <h1
          style={{
            fontSize: 'clamp(3rem, 8vw, 6rem)',
            fontWeight: 800,
            color: '#ffffff',
            lineHeight: 1.05,
            letterSpacing: '-2px',
            margin: '0 0 1.5rem',
          }}
        >
          Earn Yield on
          <br />
          Your Bitcoin
        </h1>

        {/* Subtitle */}
        <p
          style={{
            fontSize: 'clamp(1rem, 2vw, 1.15rem)',
            color: 'rgba(255,255,255,0.65)',
            maxWidth: 520,
            lineHeight: 1.7,
            margin: '0 0 2.5rem',
          }}
        >
          First protocol to eliminate impermanent loss through dynamic leverage
          rebalancing. Maximize your BTC returns on Starknet L2.
        </p>

        {/* CTA */}
        <StarBorder as="button" color="#4444cc" speed="4s" onClick={handleCTA}>
          <span
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
              fontWeight: 600,
              fontSize: '1rem',
            }}
          >
            {isConnected ? 'Open Vault' : 'Launch App'}
            <svg
              width="18"
              height="18"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
            >
              <path
                d="M13 7l5 5m0 0l-5 5m5-5H6"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          </span>
        </StarBorder>
      </div>

      {/* Features numbered scroll section */}
      <div style={{ position: 'relative', zIndex: 1 }}>
        <FeaturesSection />
      </div>

      {/* Wallet Connection Modal */}
      <WalletModal
        isOpen={isWalletModalOpen}
        onClose={() => setIsWalletModalOpen(false)}
      />
    </div>
  );
}
