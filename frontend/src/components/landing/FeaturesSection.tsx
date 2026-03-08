import { useEffect, useRef, useState } from 'react';
import './FeaturesSection.css';

const features = [
  {
    num: '01',
    title: 'Deposit and Earn',
    description:
      'Deposit your wBTC into the Vault. You receive syBTC shares that represent your position. Your Bitcoin starts generating yield immediately through our leveraged AMM engine.',
  },
  {
    num: '02',
    title: 'Leveraged AMM Engine',
    description:
      'The LEVAMM contract amplifies your returns by managing leveraged positions on concentrated liquidity pools. It tracks debt-to-value ratios in real time and adjusts exposure automatically to maximize yield while keeping risk under control.',
  },
  {
    num: '03',
    title: 'Autonomous Rebalancing',
    description:
      'The VirtualPool monitors every position and triggers on-chain rebalancing when leverage drifts beyond safe thresholds. Over-levered or under-levered, the protocol corrects itself. No human intervention. No impermanent loss.',
  },
  {
    num: '04',
    title: 'Stake and Compound',
    description:
      'Stake your wBTC directly — the protocol auto-deposits and stakes in a single transaction. Earn additional protocol rewards on top of base vault yield. Unstake and withdraw your wBTC in one click. Fully non-custodial, fully transparent, powered by Cairo smart contracts on Starknet.',
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
