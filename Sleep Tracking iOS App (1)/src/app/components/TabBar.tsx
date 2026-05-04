import React from 'react';
import { Moon, BarChart2, Pill, HeartPulse, PersonStanding } from 'lucide-react';
import { useTheme, Tab } from '../App';

const TABS: { id: Tab; label: string; Icon: React.ElementType }[] = [
  { id: 'sleep',    label: 'Sleep',    Icon: Moon           },
  { id: 'trends',   label: 'Insights', Icon: BarChart2      },
  { id: 'protocol', label: 'Protocol', Icon: Pill           },
  { id: 'biology',  label: 'Biology',  Icon: HeartPulse     },
  { id: 'activity', label: 'Activity', Icon: PersonStanding },
];

export function TabBar() {
  const { isDark, colors, activeTab, setActiveTab } = useTheme();

  return (
    <div
      style={{
        backgroundColor: isDark ? 'rgba(8,8,18,0.96)' : 'rgba(245,245,252,0.96)',
        borderTopColor: colors.border,
        borderTopWidth: 1,
        backdropFilter: 'blur(20px)',
      }}
      className="flex items-center pb-1 flex-shrink-0"
    >
      {TABS.map(({ id, label, Icon }) => {
        const active = activeTab === id;
        return (
          <button
            key={id}
            onClick={() => setActiveTab(id)}
            className="flex-1 flex flex-col items-center gap-0.5 py-2"
          >
            <div
              style={{
                width: 32, height: 32, borderRadius: 10,
                backgroundColor: active ? `${colors.brand}28` : 'transparent',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                transition: 'all 0.2s',
              }}
            >
              <Icon size={20} style={{ color: active ? colors.brand : colors.subtext }} strokeWidth={active ? 2.2 : 1.6} />
            </div>
            <span style={{ color: active ? colors.brand : colors.subtext, fontSize: 9, letterSpacing: '-0.1px' }}>
              {label}
            </span>
          </button>
        );
      })}
    </div>
  );
}
