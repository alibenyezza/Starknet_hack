import { useEffect, useState } from 'react';
import CountUp from './CountUp';

interface LoadingScreenProps {
  onComplete: () => void;
}

export default function LoadingScreen({ onComplete }: LoadingScreenProps) {
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    const duration = 500; // 0.5 seconds
    const steps = 100;
    const interval = duration / steps;

    const timer = setInterval(() => {
      setProgress((prev) => {
        if (prev >= 99) {
          clearInterval(timer);
          setTimeout(onComplete, 100);
          return 99;
        }
        return prev + 1;
      });
    }, interval);

    return () => clearInterval(timer);
  }, [onComplete]);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black">
      <div className="flex flex-col items-center gap-4">
          <div className="text-6xl font-bold gradient-text">
            <CountUp from={0} to={progress} duration={0.05} className="inline" />%
          </div>

          {/* Progress Bar */}
          <div className="w-64 h-1 bg-gray-800 rounded-full overflow-hidden">
            <div
              className="h-full bg-gradient-to-r from-primary-500 to-primary-400 transition-all duration-100 ease-linear"
              style={{ width: `${progress}%` }}
            />
          </div>

          <p className="text-sm text-gray-500 mt-2">Loading StarkYield...</p>
      </div>
    </div>
  );
}
