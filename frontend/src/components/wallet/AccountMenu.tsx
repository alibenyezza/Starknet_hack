import { useState, useRef, useEffect } from 'react';
import { useAccount, useDisconnect } from '@starknet-react/core';
import { formatAddress } from '@/utils/format';
import { IoChevronDown, IoExitOutline, IoCopyOutline } from 'react-icons/io5';
import StarBorder from '@/components/ui/StarBorder';

interface AccountMenuProps {
  onDisconnect?: () => void;
}

export function AccountMenu({ onDisconnect }: AccountMenuProps) {
  const { address } = useAccount();
  const { disconnect } = useDisconnect();
  const [isOpen, setIsOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    if (isOpen) {
      document.addEventListener('mousedown', handleClickOutside);
    }

    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [isOpen]);

  const handleCopyAddress = async () => {
    if (address) {
      await navigator.clipboard.writeText(address);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const handleDisconnect = () => {
    disconnect();
    if (onDisconnect) {
      onDisconnect();
    }
    setIsOpen(false);
  };

  if (!address) return null;

  return (
    <div className="relative" ref={menuRef}>
      {/* Trigger Button */}
      <StarBorder
        as="button"
        color="#4444cc"
        speed="4s"
        thickness={1}
        onClick={() => setIsOpen(!isOpen)}
        style={{ cursor: 'pointer' }}
      >
        <span style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontWeight: 600, fontSize: '0.85rem' }}>
          <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#4ade80', flexShrink: 0 }} />
          {formatAddress(address)}
          <IoChevronDown style={{ width: 14, height: 14, transition: 'transform 0.2s', transform: isOpen ? 'rotate(180deg)' : 'none' }} />
        </span>
      </StarBorder>

      {/* Dropdown Menu */}
      {isOpen && (
        <div className="absolute right-0 mt-2 w-64 bg-gray-950 border border-gray-800 rounded-xl shadow-2xl overflow-hidden animate-scale-in z-50">
          {/* Address Header */}
          <div className="p-4 border-b border-gray-800 bg-black/40">
            <div className="text-xs text-gray-400 mb-1">Connected Wallet</div>
            <div className="flex items-center justify-between gap-2">
              <span className="text-white font-mono text-sm">{formatAddress(address)}</span>
              <button
                onClick={handleCopyAddress}
                className="p-2 hover:bg-gray-800 rounded-lg transition-colors relative"
                title="Copy address"
              >
                <IoCopyOutline className="w-4 h-4 text-gray-400 hover:text-white" />
                {copied && (
                  <span className="absolute -top-8 right-0 bg-primary-500 text-black text-xs px-2 py-1 rounded">
                    Copied!
                  </span>
                )}
              </button>
            </div>
            <div className="mt-2 text-xs text-gray-500">
              Full address: {address?.slice(0, 8)}...{address?.slice(-8)}
            </div>
          </div>

          {/* Menu Items */}
          <div className="p-2">
            <button
              onClick={handleDisconnect}
              className="w-full flex items-center gap-3 px-4 py-3 hover:bg-gray-800 rounded-lg transition-colors group"
            >
              <IoExitOutline className="w-5 h-5 text-danger-400" />
              <div className="flex-1 text-left">
                <div className="text-white font-medium group-hover:text-danger-400 transition-colors">
                  Disconnect
                </div>
                <div className="text-xs text-gray-500">Sign out of wallet</div>
              </div>
            </button>
          </div>

          {/* Footer Info */}
          <div className="px-4 py-3 border-t border-gray-800 bg-black/20">
            <div className="text-xs text-gray-500">
              Connected to <span className="text-primary-400 font-medium">Starknet</span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
