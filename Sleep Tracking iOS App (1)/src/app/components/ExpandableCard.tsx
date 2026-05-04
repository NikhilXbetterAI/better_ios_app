import React, { useState } from 'react';
import { ChevronDown } from 'lucide-react';
import { useTheme } from '../App';

interface ExpandableCardProps {
  title: string;
  icon: React.ReactNode;
  iconBg?: string;
  summary?: React.ReactNode;
  defaultExpanded?: boolean;
  children: React.ReactNode;
}

export function ExpandableCard({
  title, icon, iconBg, summary, defaultExpanded = false, children,
}: ExpandableCardProps) {
  const { colors } = useTheme();
  const [expanded, setExpanded] = useState(defaultExpanded);

  return (
    <div
      style={{ backgroundColor: colors.card }}
      className="rounded-2xl overflow-hidden"
    >
      {/* Header row */}
      <button
        onClick={() => setExpanded(e => !e)}
        className="w-full flex items-center gap-3 p-4 text-left"
      >
        {iconBg ? (
          <div
            style={{ backgroundColor: iconBg }}
            className="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0"
          >
            {icon}
          </div>
        ) : (
          <div className="flex-shrink-0">{icon}</div>
        )}

        <div className="flex-1 min-w-0">
          <div
            style={{ color: colors.subtext, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: 2 }}
          >
            {title}
          </div>
          {!expanded && summary && (
            <div style={{ color: colors.text }}>{summary}</div>
          )}
        </div>

        <ChevronDown
          size={16}
          style={{
            color: colors.subtext,
            transform: expanded ? 'rotate(180deg)' : 'rotate(0deg)',
            transition: 'transform 0.3s ease',
            flexShrink: 0,
          }}
        />
      </button>

      {/* Expandable content */}
      <div
        style={{
          maxHeight: expanded ? '800px' : '0px',
          overflow: 'hidden',
          transition: 'max-height 0.35s cubic-bezier(0.4,0,0.2,1)',
        }}
      >
        <div className="px-4 pb-4">
          {children}
        </div>
      </div>
    </div>
  );
}
