import React, { useState } from 'react';
import { AreaChart, Area, ResponsiveContainer, Tooltip } from 'recharts';
import { Heart, Activity, Scale, Percent, Wind, Thermometer, Droplets, ChevronRight } from 'lucide-react';
import { useTheme } from '../App';
import { biologyData } from '../data/sleepData';

// ── Gauge Arc (semicircle) ─────────────────────────────────────────────────────
function GaugeArc({ pct, color, isDark }: { pct: number; color: string; isDark: boolean }) {
  const W = 90, H = 52, R = 38, CX = 45, CY = 52;
  const startAngle = Math.PI; // 180°
  const endAngle = 0;        // 0°
  const angle = startAngle + (endAngle - startAngle) * (1 - pct / 100); // fill from left
  const arcLength = Math.PI * R; // half-circle

  const toXY = (a: number) => ({ x: CX + R * Math.cos(a), y: CY + R * Math.sin(a) });
  const start = toXY(startAngle);
  const current = toXY(angle);
  const largeArc = angle - startAngle > Math.PI ? 1 : 0;

  // Background track
  const bStart = toXY(startAngle);
  const bEnd = toXY(endAngle);

  return (
    <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`}>
      {/* Track */}
      <path d={`M ${bStart.x} ${bStart.y} A ${R} ${R} 0 0 1 ${bEnd.x} ${bEnd.y}`}
        fill="none" stroke={isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.08)'}
        strokeWidth={7} strokeLinecap="round" />
      {/* Green zone (good range) */}
      <path d={`M ${toXY(Math.PI * 0.25).x} ${toXY(Math.PI * 0.25).y} A ${R} ${R} 0 0 1 ${toXY(Math.PI * 0.55).x} ${toXY(Math.PI * 0.55).y}`}
        fill="none" stroke={isDark ? 'rgba(52,199,89,0.22)' : 'rgba(52,199,89,0.18)'} strokeWidth={7} strokeLinecap="round" />
      {/* Fill arc */}
      <path d={`M ${start.x} ${start.y} A ${R} ${R} 0 ${largeArc} 1 ${current.x} ${current.y}`}
        fill="none" stroke={color} strokeWidth={7} strokeLinecap="round" />
      {/* Dot */}
      <circle cx={current.x} cy={current.y} r={5} fill={color} />
    </svg>
  );
}

// ── Horizontal Range Gauge ─────────────────────────────────────────────────────
function RangeGauge({ value, min, max, color, isDark, colors }: {
  value: number; min: number; max: number; color: string; isDark: boolean; colors: any;
}) {
  const pct = ((value - min) / (max - min)) * 100;
  return (
    <div className="relative" style={{ height: 32, display: 'flex', alignItems: 'center' }}>
      {/* Track segments: poor | fair | good | excellent */}
      <div className="flex w-full gap-0.5 rounded-full overflow-hidden" style={{ height: 10 }}>
        {[
          { color: isDark ? '#3A1A00' : '#FFE5C0', w: 20 },
          { color: isDark ? '#3A2200' : '#FFD89E', w: 20 },
          { color: isDark ? '#1A3A00' : '#C8F0C8', w: 40 },
          { color: isDark ? '#003A3A' : '#C0F0F0', w: 20 },
        ].map((seg, i) => (
          <div key={i} style={{ flex: seg.w, backgroundColor: seg.color, height: '100%' }} />
        ))}
      </div>
      {/* Thumb */}
      <div
        style={{
          position: 'absolute', left: `${Math.min(Math.max(pct, 2), 98)}%`,
          top: '50%', transform: 'translate(-50%, -50%)',
          width: 16, height: 16, borderRadius: '50%',
          backgroundColor: color, border: '2.5px solid white',
          boxShadow: '0 2px 6px rgba(0,0,0,0.4)',
        }}
      />
    </div>
  );
}

// ── Sparkline ─────────────────────────────────────────────────────────────────
function Sparkline({ data, color }: { data: number[]; color: string }) {
  const chartData = data.map((v, i) => ({ i, v }));
  return (
    <ResponsiveContainer width="100%" height={50}>
      <AreaChart data={chartData} margin={{ top: 4, right: 0, bottom: 0, left: 0 }}>
        <defs>
          <linearGradient id={`spark_${color.replace('#','')}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity={0.35} />
            <stop offset="100%" stopColor={color} stopOpacity={0} />
          </linearGradient>
        </defs>
        <Area type="monotone" dataKey="v" stroke={color} strokeWidth={1.5}
          fill={`url(#spark_${color.replace('#','')})`} dot={false} />
        <Tooltip content={() => null} />
      </AreaChart>
    </ResponsiveContainer>
  );
}

// ── Rating color ──────────────────────────────────────────────────────────────
function ratingColor(rating: string, colors: any) {
  if (rating === 'Good' || rating === 'Acceptable' || rating === 'Normal') return colors.green;
  if (rating === 'Fair' || rating === 'Stabilizing') return colors.orange;
  if (rating === 'Increasing') return colors.red;
  return colors.subtext;
}

// ── VO2 Max Card ──────────────────────────────────────────────────────────────
function Vo2Card({ colors, isDark }: { colors: any; isDark: boolean }) {
  const d = biologyData.vo2Max;
  return (
    <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
      <div className="flex items-center gap-1.5 mb-3">
        <Wind size={13} color={colors.subtext} />
        <span style={{ color: colors.subtext, fontSize: 12 }}>VO₂ Max</span>
      </div>
      <div className="flex items-end justify-between">
        <div>
          <div style={{ color: colors.text, fontSize: 32, fontWeight: 700, letterSpacing: '-0.5px', lineHeight: 1 }}>
            {d.value}
          </div>
          <div style={{ color: ratingColor(d.rating, colors), fontSize: 14, fontWeight: 600, marginTop: 3 }}>{d.rating}</div>
          <div style={{ color: colors.subtext, fontSize: 10, marginTop: 1 }}>mL/kg/min · 7-day avg</div>
        </div>
        <RangeGauge value={d.value} min={30} max={65} color={colors.orange} isDark={isDark} colors={colors} />
      </div>
      <div className="mt-3 pt-2" style={{ borderTopColor: colors.border, borderTopWidth: 0.5 }}>
        <div className="flex justify-between">
          {['Poor','Fair','Good','Excellent'].map((l, i) => (
            <span key={l} style={{ color: colors.subtext, fontSize: 9 }}>{l}</span>
          ))}
        </div>
      </div>
    </div>
  );
}

// ── HRV Baseline Card ─────────────────────────────────────────────────────────
function HRVCard({ colors, isDark }: { colors: any; isDark: boolean }) {
  const d = biologyData.hrv;
  return (
    <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
      <div className="flex items-center gap-1.5 mb-2">
        <Activity size={13} color={colors.subtext} />
        <span style={{ color: colors.subtext, fontSize: 12 }}>HRV Baselines</span>
      </div>
      <Sparkline data={d.history} color={colors.teal} />
      <div style={{ color: colors.text, fontSize: 28, fontWeight: 700, marginTop: 2, letterSpacing: '-0.5px', lineHeight: 1 }}>
        {d.value} <span style={{ fontSize: 14, color: colors.subtext, fontWeight: 400 }}>ms</span>
      </div>
      <div className="flex items-center gap-1.5 mt-1">
        <div style={{ width: 7, height: 7, borderRadius: '50%', backgroundColor: colors.teal }} />
        <span style={{ color: colors.teal, fontSize: 13, fontWeight: 600 }}>{d.rating}</span>
      </div>
    </div>
  );
}

// ── RHR Card ──────────────────────────────────────────────────────────────────
function RHRCard({ colors, isDark }: { colors: any; isDark: boolean }) {
  const d = biologyData.rhr;
  return (
    <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
      <div className="flex items-center gap-1.5 mb-2">
        <Heart size={13} color={colors.subtext} />
        <span style={{ color: colors.subtext, fontSize: 12 }}>RHR Baselines</span>
      </div>
      <div style={{ color: colors.text, fontSize: 24, fontWeight: 700, letterSpacing: '-0.4px' }}>
        {d.value} <span style={{ fontSize: 12, color: colors.subtext }}>bpm</span>
      </div>
      <div style={{ color: ratingColor(d.rating, colors), fontSize: 13, fontWeight: 600, marginBottom: 6 }}>{d.rating}</div>
      <GaugeArc pct={55} color={colors.orange} isDark={isDark} />
      <div className="flex justify-between mt-1">
        <span style={{ color: colors.subtext, fontSize: 9 }}>−</span>
        <span style={{ color: colors.subtext, fontSize: 9 }}>+</span>
      </div>
    </div>
  );
}

// ── Weight Card ───────────────────────────────────────────────────────────────
function WeightCard({ colors, isDark }: { colors: any; isDark: boolean }) {
  const d = biologyData.weight;
  return (
    <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
      <div className="flex items-center gap-1.5 mb-3">
        <Scale size={13} color={colors.subtext} />
        <span style={{ color: colors.subtext, fontSize: 12 }}>Weight</span>
      </div>
      <div className="flex items-end gap-4">
        <div>
          <div style={{ color: colors.text, fontSize: 28, fontWeight: 700, letterSpacing: '-0.5px', lineHeight: 1 }}>
            {d.value} <span style={{ fontSize: 13, color: colors.subtext }}>{d.unit}</span>
          </div>
          <div className="flex items-center gap-1 mt-2">
            <div style={{ width: 7, height: 7, borderRadius: '50%', backgroundColor: colors.orange }} />
            <span style={{ color: colors.orange, fontSize: 13, fontWeight: 600 }}>{d.rating}</span>
          </div>
        </div>
        <div className="flex-1">
          <Sparkline data={d.history} color={colors.indigo} />
        </div>
      </div>
    </div>
  );
}

// ── Body Composition Cards (Lean + Fat) ───────────────────────────────────────
function BodyCompCards({ colors, isDark }: { colors: any; isDark: boolean }) {
  return (
    <div className="grid grid-cols-2 gap-3">
      {/* Lean Body Mass */}
      <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
        <div className="flex items-center gap-1 mb-2">
          <Activity size={11} color={colors.subtext} />
          <span style={{ color: colors.subtext, fontSize: 11 }}>Lean Mass</span>
        </div>
        <div style={{ color: colors.text, fontSize: 22, fontWeight: 700, letterSpacing: '-0.4px' }}>
          {biologyData.leanBodyMass.value}
        </div>
        <div style={{ color: colors.subtext, fontSize: 11 }}>{biologyData.leanBodyMass.unit}</div>
        <Sparkline data={biologyData.leanBodyMass.history} color={colors.blue} />
        <div className="flex items-center gap-1 mt-1">
          <div style={{ width: 6, height: 6, borderRadius: '50%', backgroundColor: colors.subtext }} />
          <span style={{ color: colors.subtext, fontSize: 11 }}>No trend</span>
        </div>
      </div>

      {/* Body Fat */}
      <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
        <div className="flex items-center gap-1 mb-2">
          <Percent size={11} color={colors.subtext} />
          <span style={{ color: colors.subtext, fontSize: 11 }}>Body Fat</span>
        </div>
        <div style={{ color: colors.text, fontSize: 22, fontWeight: 700, letterSpacing: '-0.4px' }}>
          {biologyData.bodyFat.value}<span style={{ fontSize: 14 }}>%</span>
        </div>
        <div style={{ color: colors.green, fontSize: 12, fontWeight: 600, marginBottom: 4 }}>Acceptable</div>
        <GaugeArc pct={42} color={colors.green} isDark={isDark} />
      </div>
    </div>
  );
}

// ── Vitals Row ─────────────────────────────────────────────────────────────────
function VitalsRow({ colors, isDark }: { colors: any; isDark: boolean }) {
  const vitals = [
    { label: 'Blood O₂', value: `${biologyData.bloodOxygen.value}%`, icon: <Droplets size={14} color={colors.cyan} />, color: colors.cyan, sub: 'Normal' },
    { label: 'Temp',     value: `${biologyData.temperature.value}°`, icon: <Thermometer size={14} color={colors.orange} />, color: colors.orange, sub: 'Normal' },
    { label: 'Resp Rate', value: '14.2', icon: <Wind size={14} color={colors.teal} />, color: colors.teal, sub: 'br/min' },
  ];
  return (
    <div className="flex gap-2">
      {vitals.map(v => (
        <div key={v.label} className="flex-1 rounded-2xl p-3" style={{ backgroundColor: colors.card }}>
          <div className="mb-2">{v.icon}</div>
          <div style={{ color: colors.text, fontSize: 16, fontWeight: 700 }}>{v.value}</div>
          <div style={{ color: colors.subtext, fontSize: 10 }}>{v.label}</div>
          <div style={{ color: v.color, fontSize: 10, fontWeight: 600 }}>{v.sub}</div>
        </div>
      ))}
    </div>
  );
}

// ── Sleep–Biology Insights ────────────────────────────────────────────────────
function BiologyInsights({ colors, isDark }: { colors: any; isDark: boolean }) {
  const insights = [
    {
      emoji: '🫀', color: colors.teal,
      title: 'HRV + Protocol correlation',
      body: 'On protocol nights, your HRV averages 52 ms vs 39 ms baseline — a 33% improvement in autonomic recovery.',
    },
    {
      emoji: '🫁', color: colors.cyan,
      title: 'VO₂ Max & sleep quality',
      body: 'Users with VO₂ Max above 45 typically show 15% more deep sleep. Your cardiorespiratory fitness supports recovery.',
    },
    {
      emoji: '⚖️', color: colors.orange,
      title: 'Weight trend alert',
      body: 'Gradual weight increase (+1.2 kg over 30 days) may affect sleep apnea risk. Monitor RHR for early signals.',
    },
    {
      emoji: '💧', color: colors.blue,
      title: 'SpO₂ & deep sleep',
      body: 'Your 98% avg blood oxygen correlates with 21% deep sleep — optimal oxygenation supports restorative sleep stages.',
    },
  ];
  return (
    <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
      <div className="flex items-center gap-2 mb-3">
        <span style={{ color: colors.subtext, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.4px' }}>Research Connections</span>
      </div>
      <div className="space-y-2.5">
        {insights.map(ins => (
          <div key={ins.title} className="flex items-start gap-3 p-3 rounded-xl"
            style={{ backgroundColor: `${ins.color}10`, border: `1px solid ${ins.color}20` }}>
            <span style={{ fontSize: 18, flexShrink: 0 }}>{ins.emoji}</span>
            <div>
              <div style={{ color: colors.text, fontSize: 12, fontWeight: 600, marginBottom: 2 }}>{ins.title}</div>
              <div style={{ color: colors.subtext, fontSize: 11 }}>{ins.body}</div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Main BiologyTab ───────────────────────────────────────────────────────────
export function BiologyTab() {
  const { isDark, colors } = useTheme();

  return (
    <div className="flex-1 overflow-y-auto" style={{ backgroundColor: colors.bg, scrollbarWidth: 'none' }}>

      {/* Header */}
      <div className="px-5 pt-3 pb-2 flex items-center justify-between">
        <div>
          <h1 style={{ color: colors.text, fontSize: 28, fontWeight: 700, letterSpacing: '-0.5px' }}>Biology</h1>
          <p style={{ color: colors.subtext, fontSize: 13, marginTop: 1 }}>Apple Health · live data</p>
        </div>
        <div className="px-3 py-1 rounded-full" style={{ backgroundColor: `${colors.green}18`, border: `1px solid ${colors.green}35` }}>
          <span style={{ color: colors.green, fontSize: 12, fontWeight: 600 }}>Synced</span>
        </div>
      </div>

      {/* Source bar */}
      <div className="px-4 mb-3">
        <div className="flex gap-2">
          {['Apple Health','Apple Watch','Oura Ring'].map((src, i) => (
            <div key={src} className="flex items-center gap-1.5 px-2.5 py-1 rounded-full"
              style={{ backgroundColor: colors.card, border: `1px solid ${colors.border}` }}>
              <span style={{ fontSize: 12 }}>{['❤️','⌚','💍'][i]}</span>
              <span style={{ color: colors.subtext, fontSize: 10 }}>{src}</span>
            </div>
          ))}
        </div>
      </div>

      <div className="px-4 pb-6 space-y-3">
        <Vo2Card colors={colors} isDark={isDark} />

        <div className="grid grid-cols-2 gap-3">
          <HRVCard colors={colors} isDark={isDark} />
          <RHRCard colors={colors} isDark={isDark} />
        </div>

        <WeightCard colors={colors} isDark={isDark} />
        <BodyCompCards colors={colors} isDark={isDark} />
        <VitalsRow colors={colors} isDark={isDark} />
        <BiologyInsights colors={colors} isDark={isDark} />

        {/* Data disclaimer */}
        <p style={{ color: colors.subtext, fontSize: 11, textAlign: 'center', lineHeight: 1.6 }}>
          Biology data synced from Apple Health.{'\n'}Used for personalized sleep research only.
        </p>
      </div>
    </div>
  );
}