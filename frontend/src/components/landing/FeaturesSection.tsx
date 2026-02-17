import { useEffect, useRef, useState } from 'react';
import './FeaturesSection.css';

const features = [
  {
    num: '01',
    title: 'Optimized Bitcoin Yield',
    description:
      'The first IL-free Bitcoin yield protocol on Starknet L2. Deposit wBTC once and earn automatically across three DeFi strategies — no manual management, no impermanent loss.',
  },
  {
    num: '02',
    title: 'Dynamic Leverage Rebalancing',
    description:
      'Powered by Pragma Oracle real-time price feeds, StarkYield automatically detects when BTC/USDC deviate from optimal ranges and rebalances leverage positions on-chain — protecting your yield without any intervention.',
  },
  {
    num: '03',
    title: 'Multi-Strategy Diversification',
    description:
      'Your BTC is deployed across Ekubo DEX concentrated liquidity (35%), Vesu lending markets (40%), and Endur liquid staking (25%). Each strategy is managed independently and rebalanced dynamically to maximize risk-adjusted APY.',
  },
  {
    num: '04',
    title: 'Non-Custodial & Transparent',
    description:
      "All logic runs on Cairo smart contracts, fully verified by Starknet's ZK proof system. You hold your syBTC vault shares and can redeem at any time. No admin keys, no rug vectors — pure on-chain execution.",
  },
];

export default function FeaturesSection() {
  const [activeIndex, setActiveIndex] = useState(0);
  const [progress, setProgress] = useState(25);
  const itemRefs = useRef<(HTMLLIElement | null)[]>([]);

  useEffect(() => {
    const observers: IntersectionObserver[] = [];

    itemRefs.current.forEach((el, i) => {
      if (!el) return;
      const obs = new IntersectionObserver(
        ([entry]) => {
          if (entry.isIntersecting) {
            setActiveIndex(i);
            setProgress(((i + 1) / features.length) * 100);
          }
        },
        { threshold: 0.35, rootMargin: '-5% 0px -45% 0px' }
      );
      obs.observe(el);
      observers.push(obs);
    });

    return () => observers.forEach(obs => obs.disconnect());
  }, []);

  return (
    <section className="features-section">
      {/* Sticky header */}
      <div className="features-header">
        <div className="features-progress-bar">
          <div className="features-progress-fill" style={{ width: `${progress}%` }} />
        </div>
        <div className="features-header-inner">
          <h2 className="features-header-title">
            How StarkYield Works<span className="features-header-dot">.</span>
          </h2>
          <div className="features-header-counter">
            {String(activeIndex + 1).padStart(2, '0')} / {String(features.length).padStart(2, '0')}
          </div>
        </div>
      </div>

      {/* Items */}
      <ul className="features-list">
        {features.map((f, i) => (
          <li
            key={f.num}
            ref={el => { itemRefs.current[i] = el; }}
            className={`features-item${i === activeIndex ? ' active' : ''}`}
          >
            <div className="features-item-inner">
              <div className="features-item-number">
                <span className={`features-num${i === activeIndex ? ' active' : ''}`}>
                  {f.num}.
                </span>
              </div>
              <div className="features-item-content">
                <h3 className={`features-item-title${i === activeIndex ? ' active' : ''}`}>
                  {f.title}
                </h3>
                <p className={`features-item-desc${i === activeIndex ? ' active' : ''}`}>
                  {f.description}
                </p>
              </div>
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}
