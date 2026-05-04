import React, { useState } from 'react';
import {
  ChevronDown, ChevronLeft, ChevronRight, X, MapPin, Bell,
  Sun, Moon, Settings, Download, User, Navigation, Check,
  Activity, Shield, Target, Pill,
} from 'lucide-react';
import { useTheme } from '../App';
import { weeklyData, recentNotifications } from '../data/sleepData';

// ── Activity Status Options ────────────────────────────────────────────────────
const STATUS_OPTIONS = [
  { id: 'active',    label: 'Active',     desc: 'Staying engaged and healthy',   emoji: '🏃',  bg: '#22C55E', selected: true  },
  { id: 'traveling', label: 'Traveling',  desc: 'Away from home / time zone change', emoji: '✈️', bg: '#3B82F6', selected: false },
  { id: 'sick',      label: 'Sick',       desc: 'Resting from illness',           emoji: '🤒',  bg: '#EAB308', selected: false },
  { id: 'injured',   label: 'Injured',    desc: 'Recovering from an injury',      emoji: '🩹',  bg: '#EF4444', selected: false },
  { id: 'jetlag',    label: 'Jet Lagged', desc: 'Adjusting to a new time zone',  emoji: '🌐',  bg: '#A855F7', selected: false },
  { id: 'resting',   label: 'On A Break', desc: 'Taking time off from training',  emoji: '🏖️',  bg: '#0EA5E9', selected: false },
];

// ── Circular Ring (activity ring) ─────────────────────────────────────────────
function ActivityRing({ pct, color, size = 58, stroke = 7, label, value }: {
  pct: number; color: string; size?: number; stroke?: number; label: string; value: string;
}) {
  const r = (size - stroke * 2) / 2;
  const circ = 2 * Math.PI * r;
  const cx = size / 2, cy = size / 2;
  return (
    <div className="flex flex-col items-center gap-1">
      <div style={{ position: 'relative', width: size, height: size }}>
        <svg width={size} height={size}>
          <circle cx={cx} cy={cy} r={r} fill="none" stroke={`${color}22`} strokeWidth={stroke} />
          <circle cx={cx} cy={cy} r={r} fill="none" stroke={color} strokeWidth={stroke}
            strokeLinecap="round" strokeDasharray={circ}
            strokeDashoffset={circ * (1 - pct / 100)}
            transform={`rotate(-90 ${cx} ${cy})`} />
        </svg>
        <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <span style={{ color, fontSize: 13, fontWeight: 700 }}>{value}</span>
        </div>
      </div>
      <span style={{ fontSize: 9, color: '#8E8E9A', textAlign: 'center' }}>{label}</span>
    </div>
  );
}

// ── Status Modal ──────────────────────────────────────────────────────────────
function StatusModal({ current, onClose, onSelect, colors, isDark }: {
  current: string; onClose: () => void; onSelect: (id: string) => void; colors: any; isDark: boolean;
}) {
  const [selected, setSelected] = useState(current);

  return (
    <div
      style={{
        position: 'fixed', inset: 0, zIndex: 100,
        backgroundColor: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(8px)',
        display: 'flex', alignItems: 'flex-end', justifyContent: 'center',
      }}
      onClick={onClose}
    >
      <div
        style={{
          width: '100%', maxWidth: 390, borderRadius: '24px 24px 0 0',
          backgroundColor: isDark ? '#1A1A2E' : '#F5F5FA',
          padding: '16px 16px 32px',
          boxShadow: '0 -20px 60px rgba(0,0,0,0.6)',
        }}
        onClick={e => e.stopPropagation()}
      >
        {/* Handle */}
        <div style={{ width: 36, height: 4, borderRadius: 2, backgroundColor: isDark ? '#3A3A5A' : '#C8C8D8', margin: '0 auto 16px' }} />

        {/* Title row */}
        <div className="flex items-center justify-between mb-4">
          <button onClick={onClose}>
            <X size={20} color={colors.text} />
          </button>
          <span style={{ color: colors.text, fontSize: 17, fontWeight: 600 }}>Activity Status</span>
          <div style={{ width: 20 }} />
        </div>

        {/* Options */}
        <div className="space-y-2 mb-4">
          {STATUS_OPTIONS.map(opt => (
            <button
              key={opt.id}
              onClick={() => setSelected(opt.id)}
              className="w-full flex items-center gap-3 px-3 py-3 rounded-2xl text-left transition-all"
              style={{
                backgroundColor: selected === opt.id
                  ? (isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.05)')
                  : (isDark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.02)'),
                border: `1px solid ${selected === opt.id ? colors.border : 'transparent'}`,
              }}
            >
              <div style={{ width: 42, height: 42, borderRadius: 13, backgroundColor: opt.bg, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20, flexShrink: 0 }}>
                {opt.emoji}
              </div>
              <div className="flex-1">
                <div style={{ color: colors.text, fontSize: 15, fontWeight: 600 }}>{opt.label}</div>
                <div style={{ color: colors.subtext, fontSize: 12 }}>{opt.desc}</div>
              </div>
              <div style={{
                width: 22, height: 22, borderRadius: 11, flexShrink: 0,
                backgroundColor: selected === opt.id ? colors.brand : 'transparent',
                border: `2px solid ${selected === opt.id ? colors.brand : colors.border}`,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                {selected === opt.id && <Check size={12} color="#fff" />}
              </div>
            </button>
          ))}
        </div>

        <button
          onClick={() => { onSelect(selected); onClose(); }}
          className="w-full py-4 rounded-2xl"
          style={{ backgroundColor: isDark ? '#2A2A44' : '#E0E0F0' }}
        >
          <span style={{ color: colors.text, fontSize: 17, fontWeight: 600 }}>Update</span>
        </button>
        <p style={{ color: colors.subtext, fontSize: 11, textAlign: 'center', marginTop: 8, lineHeight: 1.5 }}>
          Updating your status will apply it to all sleep{'\n'}analysis and trends for that day.
        </p>
      </div>
    </div>
  );
}

// ── Travel Log Row ────────────────────────────────────────────────────────────
function TravelRow({ flag, city, dates, tz, colors }: { flag: string; city: string; dates: string; tz: string; colors: any }) {
  return (
    <div className="flex items-center gap-3 py-2.5" style={{ borderBottomColor: colors.border, borderBottomWidth: 0.5 }}>
      <span style={{ fontSize: 22 }}>{flag}</span>
      <div className="flex-1">
        <div style={{ color: colors.text, fontSize: 14 }}>{city}</div>
        <div style={{ color: colors.subtext, fontSize: 11 }}>{dates}</div>
      </div>
      <span style={{ color: colors.brand, fontSize: 12 }}>{tz}</span>
    </div>
  );
}

// ── Week Sleep Mini bar ───────────────────────────────────────────────────────
function WeekBars({ colors, isDark, selectedDay, onSelect }: {
  colors: any; isDark: boolean; selectedDay: number; onSelect: (i: number) => void;
}) {
  const max = Math.max(...weeklyData.map(d => d.hours));
  return (
    <div className="flex items-end gap-1.5" style={{ height: 60 }}>
      {weeklyData.map((d, i) => {
        const h = (d.hours / max) * 48;
        const isSelected = i === selectedDay;
        return (
          <button key={i} onClick={() => onSelect(i)} className="flex-1 flex flex-col items-center gap-1">
            <div style={{ width: '100%', height: h, borderRadius: '3px 3px 0 0',
              backgroundColor: isSelected ? colors.brand : (isDark ? '#1E1E36' : '#D8D8EC'), transition: 'all 0.2s' }} />
            <span style={{ color: isSelected ? colors.brand : colors.subtext, fontSize: 9 }}>{d.day[0]}</span>
          </button>
        );
      })}
    </div>
  );
}

// ── Toggle ────────────────────────────────────────────────────────────────────
function Toggle({ value, onChange, color }: { value: boolean; onChange: (v: boolean) => void; color: string }) {
  const { isDark } = useTheme();
  return (
    <button onClick={() => onChange(!value)}
      style={{ width: 44, height: 26, borderRadius: 13, backgroundColor: value ? color : (isDark ? '#2C2C4A' : '#C7C7CC'), position: 'relative', border: 'none', cursor: 'pointer', flexShrink: 0, transition: 'background-color 0.25s' }}>
      <div style={{ position: 'absolute', top: 2, left: value ? 20 : 2, width: 22, height: 22, borderRadius: '50%', backgroundColor: '#fff', boxShadow: '0 2px 6px rgba(0,0,0,0.35)', transition: 'left 0.22s cubic-bezier(0.34,1.56,0.64,1)' }} />
    </button>
  );
}

// ── Main ActivityTab ──────────────────────────────────────────────────────────
export function ActivityTab() {
  const { isDark, toggleTheme, colors } = useTheme();
  const [showModal,    setShowModal]    = useState(false);
  const [statusId,     setStatusId]     = useState('active');
  const [selectedDay,  setSelectedDay]  = useState(6);
  const [bedReminder,  setBedReminder]  = useState(true);
  const [sachetAlert,  setSachetAlert]  = useState(true);
  const [weeklyReport, setWeeklyReport] = useState(true);
  const [lowScore,     setLowScore]     = useState(true);

  const currentStatus = STATUS_OPTIONS.find(o => o.id === statusId) || STATUS_OPTIONS[0];
  const selectedWeekDay = weeklyData[selectedDay];

  // Status–based insight
  const statusInsight: Record<string, string> = {
    active:    'Great — your sleep architecture is well aligned with your active lifestyle.',
    traveling: 'Travel detected. Jet lag may reduce deep sleep. Protocol helps recalibrate your circadian rhythm.',
    sick:      'Recovery mode. Your body needs more deep sleep. Aim for 9h+ and stay hydrated.',
    injured:   'Injury recovery. Expect higher WASO and lighter sleep as your body repairs tissue.',
    jetlag:    'Jet lag active. Your deep sleep may be 30% lower until your circadian rhythm resets in 2–3 days.',
    resting:   'Rest week. Sleep quality may temporarily improve as training stress decreases.',
  };

  return (
    <>
      <div className="flex-1 overflow-y-auto" style={{ backgroundColor: colors.bg, scrollbarWidth: 'none' }}>

        {/* Header */}
        <div className="px-4 pt-3 pb-2">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              {/* Avatar */}
              <div style={{ width: 36, height: 36, borderRadius: 18, background: `linear-gradient(135deg, ${colors.brand}, ${colors.purple})`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                <span style={{ color: '#fff', fontSize: 14, fontWeight: 700 }}>AJ</span>
              </div>
              <div>
                <div style={{ color: colors.text, fontSize: 15, fontWeight: 700 }}>Alex Johnson</div>
                <div style={{ color: colors.subtext, fontSize: 11 }}>Day 21 · Protocol Active</div>
              </div>
            </div>
            {/* Location badge */}
            <div className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-full"
              style={{ backgroundColor: isDark ? '#1A1A2E' : '#E8E8F4', border: `1px solid ${colors.border}` }}>
              <Navigation size={10} color={colors.subtext} />
              <span style={{ color: colors.subtext, fontSize: 11 }}>London, UK</span>
            </div>
          </div>
        </div>

        <div className="px-4 pb-6 space-y-3">

          {/* Date selector */}
          <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
            <div className="flex items-center justify-between mb-3">
              <span style={{ color: colors.text, fontSize: 15, fontWeight: 600 }}>This Week</span>
              <span style={{ color: colors.subtext, fontSize: 12 }}>Apr 28 – May 4</span>
            </div>
            <WeekBars colors={colors} isDark={isDark} selectedDay={selectedDay} onSelect={setSelectedDay} />
            <div className="mt-2 flex items-center justify-between">
              <span style={{ color: colors.subtext, fontSize: 12 }}>{selectedWeekDay.date}</span>
              <div className="flex items-center gap-2">
                <span style={{ color: colors.text, fontSize: 13, fontWeight: 600 }}>{selectedWeekDay.hours}h</span>
                <span style={{ color: selectedWeekDay.score >= 80 ? colors.green : colors.orange, fontSize: 12, fontWeight: 600 }}>Score {selectedWeekDay.score}</span>
              </div>
            </div>
          </div>

          {/* Activity Status */}
          <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
            <div className="flex items-center justify-between mb-3">
              <span style={{ color: colors.subtext, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.4px' }}>Activity Status</span>
              <span style={{ color: colors.subtext, fontSize: 11 }}>May 4, 2026</span>
            </div>
            <button
              onClick={() => setShowModal(true)}
              className="w-full flex items-center gap-3 rounded-2xl py-3 px-4 text-left"
              style={{ backgroundColor: isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)', border: `1px solid ${colors.border}` }}
            >
              <div style={{ width: 42, height: 42, borderRadius: 13, backgroundColor: currentStatus.bg, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 22, flexShrink: 0 }}>
                {currentStatus.emoji}
              </div>
              <div className="flex-1">
                <div style={{ color: colors.text, fontSize: 15, fontWeight: 700 }}>{currentStatus.label}</div>
                <div style={{ color: colors.subtext, fontSize: 12 }}>{currentStatus.desc}</div>
              </div>
              <ChevronDown size={16} color={colors.subtext} />
            </button>

            {/* Status insight */}
            <div className="mt-3 rounded-xl p-3" style={{ backgroundColor: `${colors.brand}10`, border: `1px solid ${colors.brand}20` }}>
              <p style={{ color: colors.subtext, fontSize: 12 }}>{statusInsight[statusId]}</p>
            </div>
          </div>

          {/* Activity Rings */}
          <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
            <div className="flex items-center justify-between mb-3">
              <span style={{ color: colors.subtext, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.4px' }}>Today's Activity</span>
              <span style={{ color: colors.brand, fontSize: 12 }}>Apple Watch</span>
            </div>
            <div className="flex justify-around">
              <ActivityRing pct={72}  color="#FF2D55" label="Move"     value="72%" />
              <ActivityRing pct={85}  color="#34C759" label="Exercise" value="34m" />
              <ActivityRing pct={62}  color="#007AFF" label="Stand"    value="9h"  />
              <ActivityRing pct={90}  color={colors.teal} label="HRV"     value="52ms" size={58} stroke={7} />
            </div>
            <div className="mt-3 flex gap-2 flex-wrap">
              {[
                { label: 'Steps',   value: '8,420',   color: colors.orange },
                { label: 'Cal',     value: '487 kcal', color: colors.red   },
                { label: 'Active',  value: '34 min',   color: colors.green },
                { label: 'Flights', value: '6',        color: colors.blue  },
              ].map(s => (
                <div key={s.label} className="flex-1 rounded-xl p-2 text-center"
                  style={{ backgroundColor: colors.card2 }}>
                  <div style={{ color: s.color, fontSize: 13, fontWeight: 700 }}>{s.value}</div>
                  <div style={{ color: colors.subtext, fontSize: 9 }}>{s.label}</div>
                </div>
              ))}
            </div>
          </div>

          {/* Travel Log */}
          <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
            <div className="flex items-center justify-between mb-3">
              <span style={{ color: colors.subtext, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.4px' }}>Travel Log</span>
              <button style={{ color: colors.brand, fontSize: 12 }}>+ Add</button>
            </div>
            <TravelRow flag="🇬🇧" city="London, UK" dates="Apr 28 – May 6 · Current"  tz="GMT+1"  colors={colors} />
            <TravelRow flag="🇦🇪" city="Dubai, UAE"  dates="Apr 20 – 27 · Jet lag −3d"  tz="GMT+4"  colors={colors} />
            <TravelRow flag="🇺🇸" city="New York, USA" dates="Apr 12 – 19 · Jet lag −2d" tz="GMT−4"  colors={colors} />
            <div className="mt-2 rounded-xl p-2.5" style={{ backgroundColor: `${colors.orange}10`, border: `1px solid ${colors.orange}20` }}>
              <p style={{ color: colors.orange, fontSize: 11 }}>
                💡 Your Dubai trip (Apr 20–27) caused a 3-day jet lag pattern — deep sleep was 22% lower during adjustment.
              </p>
            </div>
          </div>

          {/* User Profile */}
          <div className="rounded-2xl overflow-hidden" style={{ backgroundColor: colors.card }}>
            <div className="px-4 pt-4 pb-2">
              <span style={{ color: colors.subtext, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.4px' }}>Profile</span>
            </div>
            {[
              { label: 'Name',         value: 'Alex Johnson'    },
              { label: 'Age',          value: '28 years'        },
              { label: 'Chronotype',   value: 'Slight Evening'  },
              { label: 'Sleep Goal',   value: '8h 00m'          },
              { label: 'Protocol Day', value: 'Day 21 of 30'    },
            ].map((row, i, arr) => (
              <div key={row.label} className="flex justify-between items-center px-4 py-3"
                style={{ borderBottomColor: i < arr.length - 1 ? colors.border : 'transparent', borderBottomWidth: 0.5 }}>
                <span style={{ color: colors.text, fontSize: 14 }}>{row.label}</span>
                <span style={{ color: colors.subtext, fontSize: 13 }}>{row.value}</span>
              </div>
            ))}
          </div>

          {/* Recent Notifications */}
          <div className="rounded-2xl overflow-hidden" style={{ backgroundColor: colors.card }}>
            <div className="px-4 pt-4 pb-2">
              <span style={{ color: colors.subtext, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.4px' }}>Recent Alerts</span>
            </div>
            {recentNotifications.slice(0, 3).map(n => (
              <div key={n.id} className="flex items-start gap-3 px-4 py-3"
                style={{ borderTopColor: colors.border, borderTopWidth: 0.5 }}>
                <span style={{ fontSize: 18 }}>{n.icon}</span>
                <div className="flex-1 min-w-0">
                  <div style={{ color: colors.text, fontSize: 13, fontWeight: n.read ? 400 : 600 }}>{n.title}</div>
                  <div style={{ color: colors.subtext, fontSize: 11 }}>{n.body}</div>
                  <div style={{ color: colors.subtext, fontSize: 10, marginTop: 1 }}>{n.date} · {n.time}</div>
                </div>
                {!n.read && <div style={{ width: 7, height: 7, borderRadius: 3.5, backgroundColor: colors.brand, marginTop: 4, flexShrink: 0 }} />}
              </div>
            ))}
          </div>

          {/* Quick Settings */}
          <div className="rounded-2xl overflow-hidden" style={{ backgroundColor: colors.card }}>
            <div className="px-4 pt-4 pb-2">
              <span style={{ color: colors.subtext, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.4px' }}>Reminders</span>
            </div>
            {[
              { label: 'Bedtime Reminder',  sub: '10:00 PM',  value: bedReminder,  onChange: setBedReminder  },
              { label: 'Sachet Reminder',   sub: '9:00 PM',   value: sachetAlert,  onChange: setSachetAlert  },
              { label: 'Weekly Report',     sub: 'Sundays',   value: weeklyReport, onChange: setWeeklyReport },
              { label: 'Low Score Alert',   sub: '< 70',      value: lowScore,     onChange: setLowScore     },
            ].map((row, i, arr) => (
              <div key={row.label} className="flex items-center gap-3 px-4 py-3"
                style={{ borderTopColor: colors.border, borderTopWidth: 0.5 }}>
                <div className="flex-1">
                  <div style={{ color: colors.text, fontSize: 14 }}>{row.label}</div>
                  {row.value && <div style={{ color: colors.brand, fontSize: 11 }}>{row.sub}</div>}
                </div>
                <Toggle value={row.value} onChange={row.onChange} color={colors.brand} />
              </div>
            ))}
          </div>

          {/* Theme + Misc */}
          <div className="rounded-2xl overflow-hidden" style={{ backgroundColor: colors.card }}>
            {[
              { label: isDark ? 'Dark Mode' : 'Light Mode', icon: isDark ? <Moon size={14} color="#fff" /> : <Sun size={14} color="#fff" />, iconBg: isDark ? colors.brand : colors.orange, onPress: toggleTheme, right: null },
              { label: 'Export Sleep Data', icon: <Download size={14} color="#fff" />, iconBg: colors.blue, onPress: () => {}, right: null },
              { label: 'Privacy & Data',    icon: <Shield size={14} color="#fff" />,   iconBg: colors.green, onPress: () => {}, right: null },
            ].map((row, i, arr) => (
              <button key={row.label} onClick={row.onPress}
                className="w-full flex items-center gap-3 px-4 py-3"
                style={{ borderTopColor: i > 0 ? colors.border : 'transparent', borderTopWidth: 0.5 }}>
                <div style={{ width: 28, height: 28, borderRadius: 8, backgroundColor: row.iconBg, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  {row.icon}
                </div>
                <span style={{ color: colors.text, fontSize: 14, flex: 1, textAlign: 'left' }}>{row.label}</span>
                <ChevronDown size={14} color={colors.subtext} style={{ transform: 'rotate(-90deg)' }} />
              </button>
            ))}
          </div>

          <p style={{ color: colors.subtext, fontSize: 11, textAlign: 'center' }}>
            Better Sleep · v1.0 · Prototype
          </p>
        </div>
      </div>

      {/* Activity Status Modal */}
      {showModal && (
        <StatusModal
          current={statusId}
          onClose={() => setShowModal(false)}
          onSelect={setStatusId}
          colors={colors}
          isDark={isDark}
        />
      )}
    </>
  );
}
