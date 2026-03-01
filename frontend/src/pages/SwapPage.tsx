import { LiFiWidget, type WidgetConfig } from '@lifi/widget';
import heroVideo from '@/assets/video/272517_small.mp4';

const widgetConfig: WidgetConfig = {
  integrator: 'StarkYield',
  appearance: 'dark',
  theme: {
    palette: {
      primary: { main: '#4444cc' },
      secondary: { main: '#4444cc' },
      background: {
        default: 'rgba(18, 18, 30, 0.92)',
        paper: 'rgba(25, 25, 45, 0.95)',
      },
    },
    shape: {
      borderRadius: 16,
      borderRadiusSecondary: 12,
    },
  },
};

export default function SwapPage() {
  return (
    <div style={{ position: 'relative', minHeight: '100vh' }}>
      {/* Video background — same as Hero */}
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

      {/* Widget container */}
      <div
        style={{
          position: 'relative',
          zIndex: 1,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          minHeight: '100vh',
          padding: 'clamp(6rem, 12vw, 9rem) 1rem 4rem',
        }}
      >
        <div style={{ borderRadius: 20, overflow: 'hidden' }}>
          <LiFiWidget {...widgetConfig} />
        </div>
      </div>
    </div>
  );
}
