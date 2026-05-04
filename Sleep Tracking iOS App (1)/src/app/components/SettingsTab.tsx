import React, { useState } from 'react';
import {
  Sun, Moon, Bell, Database, Heart, ChevronRight, Info,
  Target, Smartphone, Shield, Watch, Activity, Download, Trash2, User,
} from 'lucide-react';
import { useTheme } from '../App';

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
        width: 24, height: 24, borderRadius: '50%', backgroundColor: '#fff',
        boxShadow: '0 2px 6px rgba(0,0,0,0.3)',
        transition: 'left 0.22s cubic-bezier(0.34,1.56,0.64,1)',
      }} />
    </button>
  );
}

function Row({ icon, iconBg, label, sub, right, onPress, colors, last }: any) {
  return (
    <button
      onClick={onPress}
      className="w-full flex items-center gap-3 py-3 px-4 text-left"
      style={{ borderBottomColor: last ? 'transparent' : colors.border, borderBottomWidth: 0.5 }}
    >
      {iconBg ? (
        <div style={{ width: 30, height: 30, borderRadius: 8, backgroundColor: iconBg, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
          {icon}
        </div>
      ) : <div style={{ flexShrink: 0 }}>{icon}</div>}
      <div className="flex-1 min-w-0">
        <div style={{ color: colors.text, fontSize: 14 }}>{label}</div>
        {sub && <div style={{ color: colors.subtext, fontSize: 11, marginTop: 0.5 }}>{sub}</div>}
      </div>
      {right !== undefined ? right : <ChevronRight size={14} style={{ color: colors.subtext }} />}
    </button>
  );
}

function Section({ title, children, colors }: { title?: string; children: React.ReactNode; colors: any }) {
  return (
    <div>
      {title && <p style={{ color: colors.subtext, fontSize: 12, textTransform: 'uppercase', letterSpacing: '0.4px', paddingLeft: 4, marginBottom: 6 }}>{title}</p>}
      <div className="rounded-2xl overflow-hidden" style={{ backgroundColor: colors.card }}>{children}</div>
    </div>
  );
}

function DeviceCard({ name, status, icon, connected, color, colors }: any) {
  const [conn, setConn] = useState(connected);
  return (
    <div className="flex items-center gap-3 px-4 py-3" style={{ borderBottomColor: colors.border, borderBottomWidth: 0.5 }}>
      <div style={{ width: 34, height: 34, borderRadius: 9, backgroundColor: `${color}20`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, fontSize: 18 }}>
        {icon}
      </div>
      <div className="flex-1 min-w-0">
        <div style={{ color: colors.text, fontSize: 14 }}>{name}</div>
        <div style={{ color: conn ? colors.green : colors.subtext, fontSize: 11, marginTop: 1 }}>
          {conn ? '● Connected' : '○ Not connected'}
        </div>
      </div>
      <button
        onClick={() => setConn((c: boolean) => !c)}
        style={{
          fontSize: 12, fontWeight: 600, paddingInline: 12, paddingBlock: 5, borderRadius: 8,
          backgroundColor: conn ? `${colors.red}18` : `${colors.brand}18`,
          color: conn ? colors.red : colors.brand,
          border: `1px solid ${conn ? colors.red : colors.brand}30`,
        }}
      >
        {conn ? 'Disconnect' : 'Connect'}
      </button>
    </div>
  );
}

export function SettingsTab() {
  const { isDark, toggleTheme, colors } = useTheme();
  const [sleepGoal, setSleepGoal]     = useState(8);
  const [hrv,       setHrv]           = useState(true);
  const [autoSync,  setAutoSync]      = useState(true);

  return (
    <div className="flex-1 overflow-y-auto" style={{ backgroundColor: colors.bg, scrollbarWidth: 'none' }}>

      {/* Header */}
      <div className="px-5 pt-3 pb-3">
        <h1 style={{ color: colors.text, fontSize: 28, fontWeight: 700, letterSpacing: '-0.5px' }}>Settings</h1>
      </div>

      {/* Profile Card */}
      <div className="px-4 mb-4">
        <div className="flex items-center gap-3 p-4 rounded-2xl" style={{ backgroundColor: colors.card }}>
          <div
            className="w-14 h-14 rounded-full flex items-center justify-center flex-shrink-0"
            style={{ background: `linear-gradient(135deg, ${colors.brand}, ${colors.purple})` }}
          >
            <span style={{ color: '#fff', fontSize: 22, fontWeight: 700 }}>A</span>
          </div>
          <div className="flex-1">
            <div style={{ color: colors.text, fontSize: 17, fontWeight: 600 }}>Alex Johnson</div>
            <div style={{ color: colors.subtext, fontSize: 13 }}>Age 28 · Day 21 of Protocol</div>
          </div>
          <div className="flex flex-col items-end gap-1">
            <div style={{ backgroundColor: `${colors.green}20`, borderRadius: 8, paddingInline: 8, paddingBlock: 2, border: `1px solid ${colors.green}40` }}>
              <span style={{ color: colors.green, fontSize: 11, fontWeight: 600 }}>Active</span>
            </div>
            <span style={{ color: colors.brand, fontSize: 11 }}>90% adherence</span>
          </div>
        </div>
      </div>

      <div className="px-4 pb-8 space-y-5">

        {/* Appearance */}
        <Section title="Appearance" colors={colors}>
          <Row
            icon={isDark ? <Moon size={14} color="#fff" /> : <Sun size={14} color="#fff" />}
            iconBg={isDark ? colors.brand : colors.orange}
            label={isDark ? 'Dark Mode' : 'Light Mode'}
            sub="Switches the entire app theme"
            colors={colors} last
            right={<Toggle value={isDark} onChange={toggleTheme} color={colors.brand} />}
          />
        </Section>

        {/* Connected Devices */}
        <Section title="Connected Devices" colors={colors}>
          <DeviceCard name="Apple Watch"  icon="⌚" status="Connected"     connected={true}  color={colors.brand}  colors={colors} />
          <DeviceCard name="Apple Health" icon="❤️" status="Connected"     connected={true}  color={colors.red}    colors={colors} />
          <DeviceCard name="Oura Ring"    icon="💍" status="Connected"     connected={true}  color={colors.orange} colors={colors} />
          <DeviceCard name="Garmin"       icon="🏃" status="Not connected" connected={false} color={colors.blue}   colors={colors} />
          <div className="flex items-center gap-3 px-4 py-3">
            <div style={{ width: 34, height: 34, borderRadius: 9, backgroundColor: `${colors.purple}20`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, fontSize: 18 }}>🔴</div>
            <div className="flex-1">
              <div style={{ color: colors.text, fontSize: 14 }}>Whoop</div>
              <div style={{ color: colors.subtext, fontSize: 11, marginTop: 1 }}>○ Not connected</div>
            </div>
            <button style={{ fontSize: 12, fontWeight: 600, paddingInline: 12, paddingBlock: 5, borderRadius: 8, backgroundColor: `${colors.brand}18`, color: colors.brand, border: `1px solid ${colors.brand}30` }}>
              Connect
            </button>
          </div>
        </Section>

        {/* Sync */}
        <Section title="Data Sync" colors={colors}>
          <Row
            icon={<Activity size={14} color="#fff" />} iconBg={colors.teal}
            label="Auto Sync" sub="Sync automatically when you open the app"
            colors={colors} right={<Toggle value={autoSync} onChange={setAutoSync} color={colors.teal} />}
          />
          <Row
            icon={<Heart size={14} color="#fff" />} iconBg={colors.red}
            label="Sync Now" sub="Last synced: 2 min ago"
            colors={colors} last right={<span style={{ color: colors.green, fontSize: 12 }}>Up to date</span>}
          />
        </Section>

        {/* Sleep Goals */}
        <Section title="Sleep Goals" colors={colors}>
          <div className="px-4 py-3" style={{ borderBottomColor: colors.border, borderBottomWidth: 0.5 }}>
            <div className="flex items-center justify-between mb-3">
              <div style={{ color: colors.text, fontSize: 14 }}>Duration Goal</div>
              <span style={{ color: colors.brand, fontSize: 14, fontWeight: 700 }}>{Math.floor(sleepGoal)}h {Math.round((sleepGoal % 1) * 60)}m</span>
            </div>
            {/* Slider */}
            <div className="relative" style={{ height: 28 }}>
              <div className="absolute" style={{ top: '50%', transform: 'translateY(-50%)', left: 0, right: 0, height: 6, borderRadius: 3, backgroundColor: colors.card3 }} />
              <div className="absolute" style={{ top: '50%', transform: 'translateY(-50%)', left: 0, height: 6, width: `${((sleepGoal - 6) / 4) * 100}%`, borderRadius: 3, backgroundColor: colors.brand }} />
              <input
                type="range" min={6} max={10} step={0.25} value={sleepGoal}
                onChange={e => setSleepGoal(Number(e.target.value))}
                style={{ position: 'absolute', top: '50%', transform: 'translateY(-50%)', left: 0, right: 0, opacity: 0, cursor: 'pointer', height: 28, width: '100%' }}
              />
              <div style={{
                position: 'absolute', top: '50%', transform: 'translateY(-50%)',
                left: `calc(${((sleepGoal - 6) / 4) * 100}% - 12px)`,
                width: 24, height: 24, borderRadius: '50%',
                backgroundColor: '#fff', border: `2px solid ${colors.brand}`,
                boxShadow: '0 2px 8px rgba(0,0,0,0.3)',
              }} />
            </div>
            <div className="flex justify-between mt-1">
              <span style={{ color: colors.subtext, fontSize: 10 }}>6h</span>
              <span style={{ color: colors.subtext, fontSize: 10 }}>10h</span>
            </div>
          </div>
          <Row
            icon={<Target size={14} color="#fff" />} iconBg={colors.orange}
            label="Target Bed Time" sub="Based on your wake goal"
            colors={colors} right={<span style={{ color: colors.subtext, fontSize: 12 }}>11:00 PM</span>}
          />
          <Row
            icon={<Target size={14} color="#fff" />} iconBg={colors.green}
            label="Target Wake Time"
            colors={colors} last right={<span style={{ color: colors.subtext, fontSize: 12 }}>7:00 AM</span>}
          />
        </Section>

        {/* Tracking */}
        <Section title="Tracking" colors={colors}>
          <Row
            icon={<Shield size={14} color="#fff" />} iconBg={colors.green}
            label="HRV Tracking" sub="Overnight heart rate variability"
            colors={colors} last right={<Toggle value={hrv} onChange={setHrv} color={colors.green} />}
          />
        </Section>

        {/* Data */}
        <Section title="Data Management" colors={colors}>
          <Row
            icon={<Download size={14} color="#fff" />} iconBg={colors.blue}
            label="Export Sleep Data" sub="CSV · PDF report"
            colors={colors}
          />
          <Row
            icon={<Trash2 size={14} color="#fff" />} iconBg={isDark ? '#2C2C4A' : '#E0E0EE'}
            label="Clear Cache" colors={colors} last
            right={<span style={{ color: colors.red, fontSize: 12 }}>Clear</span>}
          />
        </Section>

        {/* About */}
        <Section title="About" colors={colors}>
          <Row
            icon={<Info size={14} color="#fff" />} iconBg={colors.brand}
            label="Better Sleep" sub="Version 1.0.0 · Web Prototype"
            colors={colors} last right={null}
          />
        </Section>

        <p style={{ color: colors.subtext, fontSize: 11, textAlign: 'center', lineHeight: 1.6 }}>
          Better Sleep · Powered by your personal data
          <br />Prototype only — not collecting real health information
        </p>

      </div>
    </div>
  );
}
