import React, { useCallback, useLayoutEffect, useRef, useState } from 'react';
import { gsap } from 'gsap';
import './StaggeredMenu.css';

// Social icon SVGs
const XIcon = () => (
  <svg viewBox="0 0 24 24" fill="currentColor" width="17" height="17">
    <path d="M13.6823 10.6218L20.2391 3H18.6854L12.9921 9.61788L8.44486 3L3.2002 3L10.0765 13.0074L3.2002 21H4.75404L10.7663 14.0113L15.5685 21H20.8132L13.6819 10.6218H13.6823ZM11.5541 13.0956L10.8574 12.0991L5.31391 4.16971H7.70053L12.1742 10.5689L12.8709 11.5655L18.6861 19.8835H16.2995L11.5541 13.096V13.0956Z" />
  </svg>
);

const DiscordIcon = () => (
  <svg viewBox="0 0 25 24" fill="currentColor" width="18" height="18">
    <path d="M19.7701 5.33005C18.4401 4.71005 17.0001 4.26005 15.5001 4.00005C15.487 3.99963 15.4739 4.00209 15.4618 4.00728C15.4497 4.01246 15.4389 4.02023 15.4301 4.03005C15.2501 4.36005 15.0401 4.79005 14.9001 5.12005C13.3091 4.88005 11.6911 4.88005 10.1001 5.12005C9.96012 4.78005 9.75012 4.36005 9.56012 4.03005C9.55012 4.01005 9.52012 4.00005 9.49012 4.00005C7.99012 4.26005 6.56012 4.71005 5.22012 5.33005C5.21012 5.33005 5.20012 5.34005 5.19012 5.35005C2.47012 9.42005 1.72012 13.38 2.09012 17.3C2.09012 17.32 2.10012 17.34 2.12012 17.35C3.92012 18.67 5.65012 19.47 7.36012 20C7.39012 20.01 7.42012 20 7.43012 19.98C7.83012 19.43 8.19012 18.85 8.50012 18.24C8.52012 18.2 8.50012 18.16 8.46012 18.15C7.89012 17.93 7.35012 17.67 6.82012 17.37C6.78012 17.35 6.78012 17.29 6.81012 17.26C6.92012 17.18 7.03012 17.09 7.14012 17.01C7.16012 16.99 7.19012 16.99 7.21012 17C10.6501 18.57 14.3601 18.57 17.7601 17C17.7801 16.99 17.8101 16.99 17.8301 17.01C17.9401 17.1 18.0501 17.18 18.1601 17.27C18.2001 17.3 18.2001 17.36 18.1501 17.38C17.6301 17.69 17.0801 17.94 16.5101 18.16C16.4701 18.17 16.4601 18.22 16.4701 18.25C16.7901 18.86 17.1501 19.44 17.5401 19.99C17.5701 20 17.6001 20.01 17.6301 20C19.3501 19.47 21.0801 18.67 22.8801 17.35C22.9001 17.34 22.9101 17.32 22.9101 17.3C23.3501 12.77 22.1801 8.84005 19.8101 5.35005C19.8001 5.34005 19.7901 5.33005 19.7701 5.33005ZM9.02012 14.91C7.99012 14.91 7.13012 13.96 7.13012 12.79C7.13012 11.62 7.97012 10.67 9.02012 10.67C10.0801 10.67 10.9201 11.63 10.9101 12.79C10.9101 13.96 10.0701 14.91 9.02012 14.91ZM15.9901 14.91C14.9601 14.91 14.1001 13.96 14.1001 12.79C14.1001 11.62 14.9401 10.67 15.9901 10.67C17.0501 10.67 17.8901 11.63 17.8801 12.79C17.8801 13.96 17.0501 14.91 15.9901 14.91Z" />
  </svg>
);

const TelegramIcon = () => (
  <svg viewBox="0 0 24 24" fill="currentColor" width="17" height="17">
    <path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.96 6.504-1.356 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z" />
  </svg>
);

const GitHubIcon = () => (
  <svg viewBox="0 0 24 24" fill="currentColor" width="18" height="18">
    <path d="M12 2C6.477 2 2 6.477 2 12c0 4.42 2.865 8.17 6.839 9.49.5.092.682-.217.682-.482 0-.237-.008-.866-.013-1.7-2.782.604-3.369-1.34-3.369-1.34-.454-1.156-1.11-1.464-1.11-1.464-.908-.62.069-.608.069-.608 1.003.07 1.531 1.03 1.531 1.03.892 1.529 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.11-4.555-4.943 0-1.091.39-1.984 1.029-2.683-.103-.253-.446-1.27.098-2.647 0 0 .84-.269 2.75 1.025A9.578 9.578 0 0112 6.836c.85.004 1.705.115 2.504.337 1.909-1.294 2.747-1.025 2.747-1.025.546 1.377.203 2.394.1 2.647.64.699 1.028 1.592 1.028 2.683 0 3.842-2.339 4.687-4.566 4.935.359.309.678.919.678 1.852 0 1.336-.012 2.415-.012 2.743 0 .267.18.578.688.48C19.138 20.167 22 16.418 22 12c0-5.523-4.477-10-10-10z" />
  </svg>
);

function getSocialIcon(label: string) {
  const lower = label.toLowerCase();
  if (lower.includes('twitter') || lower === 'x') return <XIcon />;
  if (lower.includes('discord')) return <DiscordIcon />;
  if (lower.includes('telegram')) return <TelegramIcon />;
  if (lower.includes('github')) return <GitHubIcon />;
  return <span style={{ fontSize: 13, fontWeight: 700, lineHeight: 1 }}>{label[0]}</span>;
}

export interface MenuItem {
  label: string;
  ariaLabel?: string;
  link?: string;
  onClick?: () => void;
  icon?: React.ReactNode;
}

export interface SocialItem {
  label: string;
  link: string;
}

interface StaggeredMenuProps {
  position?: 'left' | 'right';
  colors?: string[];
  items?: MenuItem[];
  socialItems?: SocialItem[];
  displaySocials?: boolean;
  displayItemNumbering?: boolean;
  className?: string;
  logoText?: string;
  logoImage?: string;
  accentColor?: string;
  isFixed?: boolean;
  closeOnClickAway?: boolean;
  onMenuOpen?: () => void;
  onMenuClose?: () => void;
  rightContent?: React.ReactNode;
  onLogoClick?: () => void;
  // Legacy props accepted but unused
  menuButtonColor?: string;
  openMenuButtonColor?: string;
  changeMenuColorOnOpen?: boolean;
}

export const StaggeredMenu = ({
  position = 'right',
  colors = ['#272757', '#1a1a44'],
  items = [],
  socialItems = [],
  displaySocials = true,
  displayItemNumbering = true,
  className,
  logoText = 'StarkYield',
  logoImage,
  accentColor = '#4444cc',
  isFixed = false,
  closeOnClickAway = true,
  onMenuOpen,
  onMenuClose,
  rightContent,
  onLogoClick,
}: StaggeredMenuProps) => {
  const [open, setOpen] = useState(false);
  const openRef = useRef(false);
  const panelRef = useRef<HTMLElement>(null);
  const preLayersRef = useRef<HTMLDivElement>(null);
  const preLayerElsRef = useRef<HTMLElement[]>([]);
  const hLine1Ref = useRef<HTMLSpanElement>(null);
  const hLine2Ref = useRef<HTMLSpanElement>(null);
  const hLine3Ref = useRef<HTMLSpanElement>(null);

  const openTlRef = useRef<gsap.core.Timeline | null>(null);
  const closeTweenRef = useRef<gsap.core.Tween | null>(null);
  const toggleBtnRef = useRef<HTMLButtonElement>(null);
  const busyRef = useRef(false);
  const itemEntranceTweenRef = useRef<gsap.core.Tween | null>(null);

  useLayoutEffect(() => {
    const ctx = gsap.context(() => {
      const panel = panelRef.current;
      const preContainer = preLayersRef.current;
      if (!panel) return;

      let preLayers: HTMLElement[] = [];
      if (preContainer) {
        preLayers = Array.from(preContainer.querySelectorAll<HTMLElement>('.sm-prelayer'));
      }
      preLayerElsRef.current = preLayers;

      const offscreen = position === 'left' ? -100 : 100;
      gsap.set([panel, ...preLayers], { xPercent: offscreen });

      const l1 = hLine1Ref.current;
      const l2 = hLine2Ref.current;
      const l3 = hLine3Ref.current;
      if (l1) gsap.set(l1, { transformOrigin: '50% 50%', rotate: 0, y: 0 });
      if (l2) gsap.set(l2, { transformOrigin: '50% 50%', scaleX: 1, opacity: 1 });
      if (l3) gsap.set(l3, { transformOrigin: '50% 50%', rotate: 0, y: 0 });
    });
    return () => ctx.revert();
  }, [position]);

  const buildOpenTimeline = useCallback(() => {
    const panel = panelRef.current;
    const layers = preLayerElsRef.current;
    if (!panel) return null;

    openTlRef.current?.kill();
    if (closeTweenRef.current) {
      closeTweenRef.current.kill();
      closeTweenRef.current = null;
    }
    itemEntranceTweenRef.current?.kill();

    const itemEls = Array.from(panel.querySelectorAll<HTMLElement>('.sm-panel-itemLabel'));
    const numberEls = Array.from(panel.querySelectorAll<HTMLElement>('.sm-panel-list[data-numbering] .sm-panel-item'));
    const socialTitle = panel.querySelector<HTMLElement>('.sm-socials-title');
    const socialLinks = Array.from(panel.querySelectorAll<HTMLElement>('.sm-socials-link'));

    const layerStates = layers.map(el => ({ el, start: Number(gsap.getProperty(el, 'xPercent')) }));
    const panelStart = Number(gsap.getProperty(panel, 'xPercent'));

    if (itemEls.length) gsap.set(itemEls, { yPercent: 140, rotate: 10 });
    if (numberEls.length) gsap.set(numberEls, { '--sm-num-opacity': 0 });
    if (socialTitle) gsap.set(socialTitle, { opacity: 0 });
    if (socialLinks.length) gsap.set(socialLinks, { y: 25, opacity: 0 });

    const tl = gsap.timeline({ paused: true });

    layerStates.forEach((ls, i) => {
      tl.fromTo(ls.el, { xPercent: ls.start }, { xPercent: 0, duration: 0.5, ease: 'power4.out' }, i * 0.07);
    });
    const lastTime = layerStates.length ? (layerStates.length - 1) * 0.07 : 0;
    const panelInsertTime = lastTime + (layerStates.length ? 0.08 : 0);
    const panelDuration = 0.65;
    tl.fromTo(panel, { xPercent: panelStart }, { xPercent: 0, duration: panelDuration, ease: 'power4.out' }, panelInsertTime);

    if (itemEls.length) {
      const itemsStart = panelInsertTime + panelDuration * 0.15;
      tl.to(itemEls, { yPercent: 0, rotate: 0, duration: 1, ease: 'power4.out', stagger: { each: 0.1, from: 'start' } }, itemsStart);
      if (numberEls.length) {
        tl.to(numberEls, { duration: 0.6, ease: 'power2.out', '--sm-num-opacity': 1, stagger: { each: 0.08, from: 'start' } }, itemsStart + 0.1);
      }
    }

    if (socialTitle || socialLinks.length) {
      const socialsStart = panelInsertTime + panelDuration * 0.4;
      if (socialTitle) tl.to(socialTitle, { opacity: 1, duration: 0.5, ease: 'power2.out' }, socialsStart);
      if (socialLinks.length) {
        tl.to(
          socialLinks,
          {
            y: 0, opacity: 1, duration: 0.55, ease: 'power3.out',
            stagger: { each: 0.08, from: 'start' },
            onComplete: () => { gsap.set(socialLinks, { clearProps: 'opacity' }); },
          },
          socialsStart + 0.04
        );
      }
    }

    openTlRef.current = tl;
    return tl;
  }, []);

  const playOpen = useCallback(() => {
    if (busyRef.current) return;
    busyRef.current = true;
    const tl = buildOpenTimeline();
    if (tl) {
      tl.eventCallback('onComplete', () => { busyRef.current = false; });
      tl.play(0);
    } else {
      busyRef.current = false;
    }
  }, [buildOpenTimeline]);

  const playClose = useCallback(() => {
    openTlRef.current?.kill();
    openTlRef.current = null;
    itemEntranceTweenRef.current?.kill();

    const panel = panelRef.current;
    const layers = preLayerElsRef.current;
    if (!panel) return;

    const all = [...layers, panel];
    closeTweenRef.current?.kill();
    const offscreen = position === 'left' ? -100 : 100;
    closeTweenRef.current = gsap.to(all, {
      xPercent: offscreen,
      duration: 0.32,
      ease: 'power3.in',
      overwrite: 'auto',
      onComplete: () => {
        const itemEls = Array.from(panel.querySelectorAll<HTMLElement>('.sm-panel-itemLabel'));
        if (itemEls.length) gsap.set(itemEls, { yPercent: 140, rotate: 10 });
        const numberEls = Array.from(panel.querySelectorAll<HTMLElement>('.sm-panel-list[data-numbering] .sm-panel-item'));
        if (numberEls.length) gsap.set(numberEls, { '--sm-num-opacity': 0 });
        const socialTitle = panel.querySelector<HTMLElement>('.sm-socials-title');
        const socialLinks = Array.from(panel.querySelectorAll<HTMLElement>('.sm-socials-link'));
        if (socialTitle) gsap.set(socialTitle, { opacity: 0 });
        if (socialLinks.length) gsap.set(socialLinks, { y: 25, opacity: 0 });
        busyRef.current = false;
      },
    });
  }, [position]);

  const animateHamburger = useCallback((opening: boolean) => {
    const l1 = hLine1Ref.current;
    const l2 = hLine2Ref.current;
    const l3 = hLine3Ref.current;
    if (!l1 || !l2 || !l3) return;
    if (opening) {
      gsap.to(l1, { y: 7, rotate: 45, duration: 0.35, ease: 'power3.inOut', overwrite: 'auto' });
      gsap.to(l2, { scaleX: 0, opacity: 0, duration: 0.2, ease: 'power3.inOut', overwrite: 'auto' });
      gsap.to(l3, { y: -7, rotate: -45, duration: 0.35, ease: 'power3.inOut', overwrite: 'auto' });
    } else {
      gsap.to(l1, { y: 0, rotate: 0, duration: 0.35, ease: 'power3.inOut', overwrite: 'auto' });
      gsap.to(l2, { scaleX: 1, opacity: 1, duration: 0.3, ease: 'power3.inOut', overwrite: 'auto' });
      gsap.to(l3, { y: 0, rotate: 0, duration: 0.35, ease: 'power3.inOut', overwrite: 'auto' });
    }
  }, []);

  const toggleMenu = useCallback(() => {
    const target = !openRef.current;
    openRef.current = target;
    setOpen(target);
    if (target) {
      onMenuOpen?.();
      playOpen();
    } else {
      onMenuClose?.();
      playClose();
    }
    animateHamburger(target);
  }, [playOpen, playClose, animateHamburger, onMenuOpen, onMenuClose]);

  const closeMenu = useCallback(() => {
    if (openRef.current) {
      openRef.current = false;
      setOpen(false);
      onMenuClose?.();
      playClose();
      animateHamburger(false);
    }
  }, [playClose, animateHamburger, onMenuClose]);

  React.useEffect(() => {
    if (!closeOnClickAway || !open) return;
    const handleClickOutside = (event: MouseEvent) => {
      if (
        panelRef.current && !panelRef.current.contains(event.target as Node) &&
        toggleBtnRef.current && !toggleBtnRef.current.contains(event.target as Node)
      ) {
        closeMenu();
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => { document.removeEventListener('mousedown', handleClickOutside); };
  }, [closeOnClickAway, open, closeMenu]);

  const handleItemClick = (item: MenuItem) => {
    if (item.onClick) {
      item.onClick();
      closeMenu();
    }
  };

  return (
    <div
      className={`${className ? className + ' ' : ''}staggered-menu-wrapper${isFixed ? ' fixed-wrapper' : ''}`}
      style={accentColor ? { ['--sm-accent' as string]: accentColor } : undefined}
      data-position={position}
      data-open={open || undefined}
    >
      <header className="staggered-menu-header" aria-label="Main navigation header">
        <button
          className="sm-logo"
          onClick={onLogoClick}
          aria-label="Go to home page"
          type="button"
        >
          <div className="sm-logo-text">
            {logoImage ? (
              <img src={logoImage} alt={logoText} className="sm-logo-img" />
            ) : (
              <div className="sm-logo-icon">SY</div>
            )}
            <span className="sm-logo-label">{logoText}</span>
          </div>
        </button>

        <div className="sm-header-right">
          {rightContent}
          <button
            ref={toggleBtnRef}
            className="sm-toggle"
            aria-label={open ? 'Close menu' : 'Open menu'}
            aria-expanded={open}
            aria-controls="staggered-menu-panel"
            onClick={toggleMenu}
            type="button"
          >
            <div className="sm-hamburger" aria-hidden="true">
              <span ref={hLine1Ref} />
              <span ref={hLine2Ref} />
              <span ref={hLine3Ref} />
            </div>
          </button>
        </div>
      </header>

      <div className="sm-panel-wrap">
        <div ref={preLayersRef} className="sm-prelayers" aria-hidden="true">
          {(() => {
            const raw = colors && colors.length ? colors.slice(0, 4) : ['#272757', '#1a1a44'];
            let arr = [...raw];
            if (arr.length >= 3) {
              const mid = Math.floor(arr.length / 2);
              arr.splice(mid, 1);
            }
            return arr.map((c, i) => (
              <div key={i} className="sm-prelayer" style={{ background: c }} />
            ));
          })()}
        </div>

        <aside id="staggered-menu-panel" ref={panelRef} className="staggered-menu-panel" aria-hidden={!open}>
          <div className="sm-panel-inner">
            <ul className="sm-panel-list" role="list" data-numbering={displayItemNumbering || undefined}>
              {items && items.length ? (
                items.map((it, idx) => (
                  <li className="sm-panel-itemWrap" key={it.label + idx}>
                    {it.onClick ? (
                      <button
                        className="sm-panel-item"
                        onClick={() => handleItemClick(it)}
                        aria-label={it.ariaLabel}
                        data-index={idx + 1}
                      >
                        <div className="sm-panel-itemLabel">
                          {it.icon && <span className="sm-panel-item-icon">{it.icon}</span>}
                          {it.label}
                        </div>
                      </button>
                    ) : (
                      <a
                        className="sm-panel-item"
                        href={it.link || '#'}
                        aria-label={it.ariaLabel}
                        data-index={idx + 1}
                      >
                        <div className="sm-panel-itemLabel">
                          {it.icon && <span className="sm-panel-item-icon">{it.icon}</span>}
                          {it.label}
                        </div>
                      </a>
                    )}
                  </li>
                ))
              ) : (
                <li className="sm-panel-itemWrap" aria-hidden="true">
                  <span className="sm-panel-item">
                    <div className="sm-panel-itemLabel">No items</div>
                  </span>
                </li>
              )}
            </ul>

            {displaySocials && socialItems && socialItems.length > 0 && (
              <div className="sm-socials" aria-label="Social links">
                <h3 className="sm-socials-title">Socials</h3>
                <ul className="sm-socials-list" role="list">
                  {socialItems.map((s, i) => (
                    <li key={s.label + i} className="sm-socials-item">
                      <a
                        href={s.link}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="sm-socials-link app-footer-social"
                        title={s.label}
                        aria-label={s.label}
                      >
                        {getSocialIcon(s.label)}
                      </a>
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        </aside>
      </div>
    </div>
  );
};

export default StaggeredMenu;
