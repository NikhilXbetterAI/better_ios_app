import React, { useState } from 'react';
import { Bell, Moon, AlarmClock, Pill, TrendingDown, Calendar, Activity, Shuffle, Check } from 'lucide-react';
import { useTheme } from '../App';
import { recentNotifications } from '../data/sleepData';

// ── iOS Toggle ────────────────────────────────────────────────────────────────
function Toggle({ value, onChange, color }: { value: boolean; onChange: (v: boolean) => void; color: string }) {
  const { isDark } = useTheme();
  return (
    <button
      onClick={() => onChange(!value)}
      style={{
        width: 48, height: 28, borderRadius: 14,
        backgroundColor: value ? color : (isDark ? '#2C2C4A' : '#C7C7CC'),
        position: 'relative', border: 'none', cursor: 'pointer',
        transition: 'background-color 0.25s', flexShrink: 0,
      }}
    >
      <div style={{
        position: 'absolute', top: 2, left: value ? 22 : 2,
        width: 24, height: 24, borderRadius: '50%',
        backgroundColor: '#fff', boxShadow: '0 2px 6px rgba(0,0,0,0.35)',
        transition: 'left 0.22s cubic-bezier(0.34,1.56,0.64,1)',
      }} />
    </button>
  );
}

// ── Reminder Row ──────────────────────────────────────────────────────────────
function ReminderRow({
  icon, iconBg, title, subtitle, enabled, onToggle, time, colors, last,
}: {
  icon: React.ReactNode; iconBg: string; title: string; subtitle?: string;
  enabled: boolean; onToggle: (v: boolean) => void; time?: string; colors: any; last?: boolean;
}) {
  return (
    <div
      className="flex items-center gap-3 px-4 py-3"
      style={{ borderBottomColor: last ? 'transparent' : colors.border, borderBottomWidth: 0.5 }}
    >
      <div style={{ width: 32, height: 32, borderRadius: 9, backgroundColor: iconBg, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        {icon}
      </div>
      <div className="flex-1 min-w-0">
        <div style={{ color: colors.text, fontSize: 14 }}>{title}</div>
        {subtitle && <div style={{ color: colors.subtext, fontSize: 11, marginTop: 1 }}>{subtitle}</div>}
        {time && enabled && (
          <div style={{ color: colors.brand, fontSize: 11, marginTop: 1 }}>{time}</div>
        )}
      </div>
      <Toggle value={enabled} onChange={onToggle} color={colors.brand} />
    </div>
  );
}

// ── Notification Feed Item ────────────────────────────────────────────────────
function NotifItem({ notif, colors }: { notif: typeof recentNotifications[0]; colors: any }) {
  return (
    <div
      className="flex items-start gap-3 px-4 py-3"
      style={{ borderBottomColor: colors.border, borderBottomWidth: 0.5 }}
    >
      <div
        style={{
          width: 36, height: 36, borderRadius: 10, flexShrink: 0,
          backgroundColor: notif.read ? colors.card2 : `${colors.brand}20`,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 18,
        }}
      >
        {notif.icon}
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-start justify-between gap-2">
          <span style={{ color: colors.text, fontSize: 13, fontWeight: notif.read ? 400 : 600 }}>{notif.title}</span>
          <span style={{ color: colors.subtext, fontSize: 10, flexShrink: 0 }}>{notif.time}</span>
        </div>
        <div style={{ color: colors.subtext, fontSize: 12, marginTop: 1 }}>{notif.body}</div>
        <div style={{ color: colors.subtext, fontSize: 10, marginTop: 2 }}>{notif.date}</div>
      </div>
      {!notif.read && (
        <div style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: colors.brand, flexShrink: 0, marginTop: 4 }} />
      )}
    </div>
  );
}

// ── Section Label ─────────────────────────────────────────────────────────────
function SectionLabel({ label, colors }: { label: string; colors: any }) {
  return (
    <p style={{ color: colors.subtext, fontSize: 12, textTransform: 'uppercase', letterSpacing: '0.4px', paddingLeft: 4, marginBottom: 6 }}>
      {label}
    </p>
  );
}

// ── Main AlertsTab ────────────────────────────────────────────────────────────
export function AlertsTab() {
  const { isDark, colors } = useTheme();

  const [bedReminder,     setBedReminder]     = useState(true);
  const [sachetReminder,  setSachetReminder]  = useState(true);
  const [wakeAlarm,       setWakeAlarm]       = useState(true);
  const [weeklyReport,    setWeeklyReport]    = useState(true);
  const [lowScoreAlert,   setLowScoreAlert]   = useState(true);
  const [sleepDebtWarn,   setSleepDebtWarn]   = useState(false);
  const [irregSchedule,   setIrregSchedule]   = useState(true);
  const [missedProtocol,  setMissedProtocol]  = useState(true);

  const unread = recentNotifications.filter(n => !n.read).length;

  return (
    <div className="flex-1 overflow-y-auto" style={{ backgroundColor: colors.bg, scrollbarWidth: 'none' }}>

      {/* Header */}
      <div className="px-5 pt-3 pb-3 flex items-end justify-between">
        <div>
          <h1 style={{ color: colors.text, fontSize: 28, fontWeight: 700, letterSpacing: '-0.5px' }}>Alerts</h1>
          <p style={{ color: colors.subtext, fontSize: 13, marginTop: 1 }}>Notifications & reminders</p>
        </div>
        {unread > 0 && (
          <div style={{ backgroundColor: colors.brand, borderRadius: 10, paddingInline: 8, paddingBlock: 3 }}>
            <span style={{ color: '#fff', fontSize: 12, fontWeight: 700 }}>{unread} new</span>
          </div>
        )}
      </div>

      <div className="px-4 pb-6 space-y-4">

        {/* Sleep Summary Banner */}
        <div
          className="rounded-2xl p-3 flex items-center gap-3"
          style={{ backgroundColor: `${colors.brand}18`, border: `1px solid ${colors.brand}30` }}
        >
          <div style={{ width: 36, height: 36, borderRadius: 10, backgroundColor: `${colors.brand}30`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Check size={18} color={colors.brand} />
          </div>
          <div>
            <div style={{ color: colors.text, fontSize: 13, fontWeight: 600 }}>Today's analysis is ready</div>
            <div style={{ color: colors.subtext, fontSize: 12 }}>Score 82 · 7h 23m · Protocol followed ✓</div>
          </div>
        </div>

        {/* Daily Reminders */}
        <div>
          <SectionLabel label="Daily Reminders" colors={colors} />
          <div className="rounded-2xl overflow-hidden" style={{ backgroundColor: colors.card }}>
            <ReminderRow
              icon={<Bell size={15} color="#fff" />} iconBg={colors.brand}
              title="Bedtime Reminder" subtitle="Wind down 30 min before your target bed time" time="10:00 PM"
              enabled={bedReminder} onToggle={setBedReminder} colors={colors}
            />
            <ReminderRow
              icon={<Pill size={15} color="#fff" />} iconBg={colors.green}
              title="Sachet Reminder" subtitle="Take your Better Sleep Formula 30–60 min before bed" time="9:00 PM"
              enabled={sachetReminder} onToggle={setSachetReminder} colors={colors}
            />
            <ReminderRow
              icon={<AlarmClock size={15} color="#fff" />} iconBg={colors.orange}
              title="Wake Alarm" subtitle="Gentle reminder to maintain your sleep schedule" time="7:00 AM"
              enabled={wakeAlarm} onToggle={setWakeAlarm} colors={colors} last
            />
          </div>
        </div>

        {/* Reports */}
        <div>
          <SectionLabel label="Reports" colors={colors} />
          <div className="rounded-2xl overflow-hidden" style={{ backgroundColor: colors.card }}>
            <ReminderRow
              icon={<Calendar size={15} color="#fff" />} iconBg={colors.indigo}
              title="Weekly Sleep Report" subtitle="Summary every Sunday at 8:00 AM" time="Sun · 8:00 AM"
              enabled={weeklyReport} onToggle={setWeeklyReport} colors={colors} last
            />
          </div>
        </div>

        {/* Smart Alerts */}
        <div>
          <SectionLabel label="Smart Alerts" colors={colors} />
          <div className="rounded-2xl overflow-hidden" style={{ backgroundColor: colors.card }}>
            <ReminderRow
              icon={<TrendingDown size={15} color="#fff" />} iconBg={colors.red}
              title="Low Sleep Score" subtitle="Alert when score drops below 70"
              enabled={lowScoreAlert} onToggle={setLowScoreAlert} colors={colors}
            />
            <ReminderRow
              icon={<Moon size={15} color="#fff" />} iconBg={colors.purple}
              title="Sleep Debt Warning" subtitle="Alert when weekly deficit exceeds 1 hour"
              enabled={sleepDebtWarn} onToggle={setSleepDebtWarn} colors={colors}
            />
            <ReminderRow
              icon={<Shuffle size={15} color="#fff" />} iconBg={colors.teal}
              title="Irregular Schedule" subtitle="Alert when bed time varies by more than 1 hour"
              enabled={irregSchedule} onToggle={setIrregSchedule} colors={colors}
            />
            <ReminderRow
              icon={<Pill size={15} color="#fff" />} iconBg={colors.orange}
              title="Protocol Miss" subtitle="Reminder the next morning if sachet was missed"
              enabled={missedProtocol} onToggle={setMissedProtocol} colors={colors} last
            />
          </div>
        </div>

        {/* Sleep Thresholds */}
        <div>
          <SectionLabel label="Alert Thresholds" colors={colors} />
          <div className="rounded-2xl overflow-hidden" style={{ backgroundColor: colors.card }}>
            {[
              { label: 'Low Score Alert',  value: '< 70', color: colors.red },
              { label: 'Min Deep Sleep',   value: '< 60 min', color: colors.indigo },
              { label: 'Max WASO',         value: '> 45 min', color: colors.orange },
              { label: 'Sleep Debt Alert', value: '> 1h deficit', color: colors.purple },
            ].map((row, i, arr) => (
              <div
                key={row.label}
                className="flex items-center justify-between px-4 py-3"
                style={{ borderBottomColor: i < arr.length - 1 ? colors.border : 'transparent', borderBottomWidth: 0.5 }}
              >
                <span style={{ color: colors.text, fontSize: 14 }}>{row.label}</span>
                <span style={{ color: row.color, fontSize: 13, fontWeight: 600 }}>{row.value}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Recent Notifications */}
        <div>
          <SectionLabel label="Recent" colors={colors} />
          <div className="rounded-2xl overflow-hidden" style={{ backgroundColor: colors.card }}>
            {recentNotifications.map(n => (
              <NotifItem key={n.id} notif={n} colors={colors} />
            ))}
          </div>
        </div>

      </div>
    </div>
  );
}
