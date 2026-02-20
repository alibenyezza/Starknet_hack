import { useEffect, useRef, useCallback } from 'react';
import './OrizonLogo.css';

export default function OrizonLogo({ size = 400, color = '#F5F5F0', waveSpeed = 3, waveAmplitude = 12 }) {
  const canvasRef = useRef(null);
  const animRef = useRef(null);
  const hoverRef = useRef(0);
  const targetHoverRef = useRef(0);
  const mouseAngleRef = useRef(0);
  const timeRef = useRef(0);

  const COUNT = 48;
  const INNER_R = 20;
  const BASE_MID_START = 32;
  const BASE_MID_END = 45;
  const BASE_OUTER_R = 55;

  const handleMouseMove = useCallback((e) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const x = e.clientX - rect.left - rect.width / 2;
    const y = e.clientY - rect.top - rect.height / 2;
    const dist = Math.sqrt(x * x + y * y);
    const maxDist = rect.width / 2;

    if (dist < maxDist * 0.85) {
      targetHoverRef.current = 1;
      mouseAngleRef.current = Math.atan2(y, x);
    } else {
      targetHoverRef.current = 0;
    }
  }, []);

  const handleMouseLeave = useCallback(() => {
    targetHoverRef.current = 0;
  }, []);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const dpr = window.devicePixelRatio || 1;

    canvas.width = size * dpr;
    canvas.height = size * dpr;
    canvas.style.width = size + 'px';
    canvas.style.height = size + 'px';
    ctx.scale(dpr, dpr);

    const center = size / 2;
    const scale = size / 200;

    const draw = (timestamp) => {
      const dt = timestamp * 0.001;
      timeRef.current = dt;

      // Smooth hover transition
      hoverRef.current += (targetHoverRef.current - hoverRef.current) * 0.08;

      ctx.clearRect(0, 0, size, size);
      ctx.lineCap = 'round';

      for (let i = 0; i < COUNT; i++) {
        const angle = (i * 2 * Math.PI) / COUNT;

        // Base wobble from original SVG
        const baseWobble = Math.sin(i * 0.2) * 3;
        const baseOuterVariation = Math.cos(i * 0.3) * 5;

        // Wave animation on hover
        const angleDiff = angle - mouseAngleRef.current;
        const waveOffset = Math.sin(angleDiff * 2 - dt * waveSpeed) * waveAmplitude * hoverRef.current;
        const breathe = Math.sin(dt * 1.5 + i * 0.13) * 2 * hoverRef.current;

        const innerR = (INNER_R) * scale;
        const midStart = (BASE_MID_START + baseWobble + waveOffset * 0.3 + breathe) * scale;
        const midEnd = (BASE_MID_END + baseWobble + waveOffset * 0.6 + breathe) * scale;
        const outerR = (BASE_OUTER_R + baseOuterVariation + waveOffset + breathe) * scale;

        const cos = Math.cos(angle);
        const sin = Math.sin(angle);

        // Inner thin line
        ctx.beginPath();
        ctx.moveTo(center + cos * innerR, center + sin * innerR);
        ctx.lineTo(center + cos * midStart, center + sin * midStart);
        ctx.strokeStyle = color;
        ctx.lineWidth = 0.6 * scale;
        ctx.stroke();

        // Middle thick line
        ctx.beginPath();
        ctx.moveTo(center + cos * midStart, center + sin * midStart);
        ctx.lineTo(center + cos * midEnd, center + sin * midEnd);
        ctx.strokeStyle = color;
        ctx.lineWidth = 2.2 * scale;
        ctx.stroke();

        // Outer thin line
        ctx.beginPath();
        ctx.moveTo(center + cos * midEnd, center + sin * midEnd);
        ctx.lineTo(center + cos * outerR, center + sin * outerR);
        ctx.strokeStyle = color;
        ctx.lineWidth = 0.6 * scale;
        ctx.stroke();
      }

      animRef.current = requestAnimationFrame(draw);
    };

    animRef.current = requestAnimationFrame(draw);

    return () => {
      if (animRef.current) cancelAnimationFrame(animRef.current);
    };
  }, [size, color, waveSpeed, waveAmplitude]);

  return (
    <canvas
      ref={canvasRef}
      className="orizon-logo"
      onMouseMove={handleMouseMove}
      onMouseLeave={handleMouseLeave}
    />
  );
}
