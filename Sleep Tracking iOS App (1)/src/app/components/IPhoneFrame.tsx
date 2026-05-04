import React from 'react';
import { Wifi, Signal } from 'lucide-react';
import { useTheme } from '../App';

export function IPhoneFrame({ children }: { children: React.ReactNode }) {
  const { isDark, colors } = useTheme();

  const outerStyle = isDark
    ? {
        background: 'linear-gradient(160deg, #2e2e3e 0%, #1a1a28 40%, #0e0e18 100%)',
        boxShadow: '0 0 0 1.5px #3a3a5a inset, 0 50px 100px rgba(0,0,0,0.9), 0 0 80px rgba(99,102,241,0.15)',
      }
    : {
        background: 'linear-gradient(160deg, #d8d8e8 0%, #c8c8da 40%, #b8b8cc 100%)',
        boxShadow: '0 0 0 1px #aaa inset, 0 40px 80px rgba(0,0,0,0.3)',
      };

  return (
    <div className="relative flex-shrink-0" style={{ width: 390, height: 852 }}>
      {/* Side buttons */}
      {[120, 170, 248].map((top, i) => (
        <div key={i} className="absolute left-[-3px] rounded-l-full"
          style={{ top, width: 3, height: i === 0 ? 36 : 64, background: isDark ? '#2a2a3a' : '#b0b0c0' }} />
      ))}
      <div className="absolute right-[-3px] rounded-r-full"
        style={{ top: 170, width: 3, height: 80, background: isDark ? '#2a2a3a' : '#b0b0c0' }} />

      {/* Phone body */}
      <div className="relative w-full h-full rounded-[52px] p-[14px]" style={outerStyle}>
        {/* Screen */}
        <div
          className="relative w-full h-full rounded-[40px] overflow-hidden flex flex-col"
          style={{ backgroundColor: colors.bg }}
        >
          {/* Status bar */}
          <div className="relative flex items-center justify-between px-6 pt-4 pb-1 flex-shrink-0" style={{ zIndex: 10 }}>
            <span style={{ color: colors.text, fontSize: 15, fontWeight: 600, letterSpacing: '-0.3px' }}>9:41</span>
            {/* Dynamic Island */}
            <div
              className="absolute left-1/2 -translate-x-1/2 top-3 rounded-full"
              style={{ width: 126, height: 36, backgroundColor: '#000', zIndex: 20 }}
            />
            <div className="flex items-center gap-1.5">
              <Signal size={13} style={{ color: colors.text }} />
              <Wifi   size={13} style={{ color: colors.text }} />
              <div className="flex items-center gap-0.5">
                <div style={{ width: 23, height: 12, border: `1.5px solid ${colors.text}`, borderRadius: 3, display: 'flex', alignItems: 'center', padding: 1.5 }}>
                  <div style={{ width: '78%', height: '100%', backgroundColor: colors.green, borderRadius: 1 }} />
                </div>
              </div>
            </div>
          </div>

          {/* Content */}
          <div className="flex-1 flex flex-col overflow-hidden">{children}</div>
        </div>
      </div>
    </div>
  );
}
