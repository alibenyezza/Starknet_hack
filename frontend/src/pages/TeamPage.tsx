import ProfileCard from '@/components/ui/ProfileCard';
import leftPhoto from '@/assets/1765037604157.jpg';
import rightPhoto from '@/assets/pfp card right.png';
import teamVideo from '@/assets/video/7260-199191197.mp4';

interface TeamPageProps {
  onNavigateHome?: () => void;
}

export default function TeamPage({ onNavigateHome: _onNavigateHome }: TeamPageProps) {
  return (
    <div
      className="relative"
      style={{
        background: 'transparent',
        height: '100vh',
        overflow: 'hidden',
        fontFamily: 'var(--font-ui)',
      }}
    >
      {/* Video background */}
      <div
        style={{
          position: 'absolute',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          width: '100%',
          height: '100%',
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
          <source src={teamVideo} type="video/mp4" />
        </video>
        {/* Dark overlay */}
        <div
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundColor: 'rgba(0, 0, 0, 0.6)',
          }}
        />
      </div>

      <div
        className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8"
        style={{
          zIndex: 2,
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        {/* Header */}
        <div className="text-center mb-12">
          <h1 className="text-5xl md:text-6xl font-bold text-white mb-4">
            Meet the{' '}
            <span style={{ color: '#ffffff' }}>Team</span>
          </h1>
          <p className="text-lg max-w-xl mx-auto" style={{ color: 'rgba(255, 255, 255, 0.75)' }}>
            The people building the future of Bitcoin yield on Starknet.
          </p>
        </div>

        {/* Cards — side by side */}
        <div
          className="flex flex-row gap-8 justify-center items-stretch"
        >
          <ProfileCard
            name=""
            role=""
            avatarUrl={leftPhoto}
            socials={{
              telegram: 'https://t.me/aliby00',
              github: 'https://github.com/alibenyezza',
              twitter: 'https://x.com/AliBENYEZZ13187',
            }}
          />
          <ProfileCard
            name=""
            role=""
            avatarUrl={rightPhoto}
            socials={{
              telegram: 'https://t.me/aiden_7788',
              github: 'https://github.com/aydi26',
              twitter: 'https://x.com/aiden_7788',
            }}
          />
        </div>
      </div>
    </div>
  );
}
