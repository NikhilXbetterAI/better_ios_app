import React, { useState } from 'react';
import {
  BarChart, Bar, XAxis, YAxis, ResponsiveContainer, Tooltip, Cell,
} from 'recharts';
import { CheckCircle2, Circle, Flame, ChevronDown, ChevronUp, Zap } from 'lucide-react';
import { useTheme } from '../App';
import { protocolData } from '../data/sleepData';

// ── Adherence Heatmap ────────────────────────────────────────────────────────
function AdherenceHeatmap({ history, colors, isDark }: { history: boolean[]; colors: any; isDark: boolean }) {
  const weeks = [history.slice(0, 7), history.slice(7, 14), history.slice(14, 21)];
  const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  return (
    <div>
      <div className="flex justify-between mb-2 px-1">
        {dayLabels.map((d, i) => (
          <span key={i} style={{ color: colors.subtext, fontSize: 10, width: 28, textAlign: 'center' }}>{d}</span>
        ))}
      </div>
      {weeks.map((week, wi) => (
        <div key={wi} className="flex justify-between mb-1.5">
          {week.map((taken, di) => (
            <div
              key={di}
              style={{
                width: 28,
                height: 28,
                borderRadius: 8,
                backgroundColor: taken
                  ? `${colors.green}30`
                  : isDark ? '#1E1E36' : '#E8E8F4',
                border: `1.5px solid ${taken ? colors.green : 'transparent'}`,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              {taken && <div style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: colors.green }} />}
            </div>
          ))}
        </div>
      ))}
      <div className="flex items-center gap-3 mt-2">
        <div className="flex items-center gap-1.5">
          <div style={{ width: 10, height: 10, borderRadius: 3, backgroundColor: colors.green, opacity: 0.6 }} />
          <span style={{ color: colors.subtext, fontSize: 10 }}>Taken</span>
        </div>
        <div className="flex items-center gap-1.5">
          <div style={{ width: 10, height: 10, borderRadius: 3, backgroundColor: isDark ? '#1E1E36' : '#E8E8F4', border: `1px solid ${colors.border}` }} />
          <span style={{ color: colors.subtext, fontSize: 10 }}>Missed</span>
        </div>
      </div>
    </div>
  );
}

// ── Impact Comparison Chart ───────────────────────────────────────────────────
function ImpactChart({ colors, isDark }: { colors: any; isDark: boolean }) {
  const data = [
    { metric: 'Deep', with: 21, without: 14 },
    { metric: 'REM',  with: 24, without: 19 },
    { metric: 'Score',with: 85, without: 71 },
    { metric: 'HRV',  with: 52, without: 39 },
  ];

  return (
    <ResponsiveContainer width="100%" height={130}>
      <BarChart data={data} margin={{ top: 4, right: 0, bottom: 0, left: -24 }} barCategoryGap="30%">
        <XAxis dataKey="metric" tick={{ fill: colors.subtext, fontSize: 10 }} axisLine={false} tickLine={false} />
        <YAxis hide />
        <Tooltip
          content={({ active, payload, label }) => {
            if (!active || !payload?.length) return null;
            return (
              <div style={{ backgroundColor: colors.card, border: `1px solid ${colors.border}`, borderRadius: 8, padding: '6px 10px' }}>
                <div style={{ color: colors.text, fontSize: 12, fontWeight: 600 }}>{label}</div>
                <div style={{ color: colors.green, fontSize: 11 }}>With: {payload[0]?.value}</div>
                <div style={{ color: colors.subtext, fontSize: 11 }}>Without: {payload[1]?.value}</div>
              </div>
            );
          }}
        />
        <Bar dataKey="with"    name="With sachet"    radius={[4,4,0,0]} fill={colors.green} opacity={0.9} />
        <Bar dataKey="without" name="Without sachet" radius={[4,4,0,0]} fill={isDark ? '#252545' : '#D1D1E0'} />
      </BarChart>
    </ResponsiveContainer>
  );
}

// ── Ingredient Row ─────────────────────────────────────────────────────────────
function IngredientRow({ name, dose, benefit, color, colors, last }: any) {
  return (
    <div className="flex items-center gap-3 py-2.5" style={{ borderBottomColor: last ? 'transparent' : colors.border, borderBottomWidth: 0.5 }}>
      <div style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: color, flexShrink: 0, marginTop: 1 }} />
      <div className="flex-1 min-w-0">
        <div style={{ color: colors.text, fontSize: 13 }}>{name}</div>
        <div style={{ color: colors.subtext, fontSize: 11 }}>{benefit}</div>
      </div>
      <span style={{ color: color, fontSize: 12, fontWeight: 600, flexShrink: 0 }}>{dose}</span>
    </div>
  );
}

// ── Main ProtocolTab ──────────────────────────────────────────────────────────
export function ProtocolTab() {
  const { isDark, colors } = useTheme();
  const [takenTonight, setTakenTonight] = useState(protocolData.takenTonight);
  const [takenAt, setTakenAt]           = useState(protocolData.takenAt);
  const [showIngredients, setShowIngredients] = useState(false);

  const handleTake = () => {
    setTakenTonight(true);
    const now = new Date();
    const h = now.getHours();
    const m = now.getMinutes().toString().padStart(2, '0');
    const period = h >= 12 ? 'PM' : 'AM';
    const h12 = h > 12 ? h - 12 : h === 0 ? 12 : h;
    setTakenAt(`${h12}:${m} ${period}`);
  };

  return (
    <div className="flex-1 overflow-y-auto" style={{ backgroundColor: colors.bg, scrollbarWidth: 'none' }}>

      {/* Header */}
      <div className="px-5 pt-3 pb-3">
        <div className="flex items-end justify-between">
          <div>
            <h1 style={{ color: colors.text, fontSize: 28, fontWeight: 700, letterSpacing: '-0.5px' }}>Protocol</h1>
            <p style={{ color: colors.subtext, fontSize: 13, marginTop: 1 }}>
              Better Sleep Formula · Day {protocolData.dayNumber}
            </p>
          </div>
          <div
            className="px-3 py-1 rounded-full"
            style={{ backgroundColor: `${colors.green}20`, border: `1px solid ${colors.green}50` }}
          >
            <span style={{ color: colors.green, fontSize: 12, fontWeight: 600 }}>Active</span>
          </div>
        </div>
      </div>

      <div className="px-4 pb-6 space-y-3">

        {/* Sachet Card — matches screenshot exactly */}
        <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
          <div className="flex items-start gap-3 mb-4">
            <span style={{ fontSize: 36 }}>💊</span>
            <div className="flex-1">
              <div style={{ color: colors.text, fontSize: 17, fontWeight: 700 }}>Better Sleep Formula</div>
              <div style={{ color: colors.subtext, fontSize: 13, marginTop: 2 }}>2 capsules · 30–60 min before bed</div>
              <div style={{ color: colors.subtext, fontSize: 12, marginTop: 1 }}>Mg · L-Theanine · Ashwagandha + 8 more</div>
            </div>
          </div>

          {takenTonight ? (
            <div>
              <div
                className="w-full rounded-2xl flex items-center justify-center gap-2 py-3.5"
                style={{ backgroundColor: colors.green }}
              >
                <CheckCircle2 size={18} color="#000" strokeWidth={2.5} />
                <span style={{ color: '#000', fontSize: 17, fontWeight: 700 }}>Taken Tonight</span>
              </div>
              <p style={{ color: colors.subtext, fontSize: 11, textAlign: 'center', marginTop: 6 }}>
                Logged at {takenAt} · Great job staying consistent!
              </p>
            </div>
          ) : (
            <div className="space-y-2">
              <button
                onClick={handleTake}
                className="w-full rounded-2xl flex items-center justify-center gap-2 py-3.5 transition-all active:scale-98"
                style={{ backgroundColor: `${colors.green}22`, border: `1.5px solid ${colors.green}` }}
              >
                <Circle size={18} color={colors.green} />
                <span style={{ color: colors.green, fontSize: 17, fontWeight: 700 }}>Mark as Taken</span>
              </button>
              <button
                className="w-full rounded-2xl flex items-center justify-center py-2.5"
                style={{ backgroundColor: colors.card2 }}
              >
                <span style={{ color: colors.subtext, fontSize: 14 }}>Remind me later</span>
              </button>
            </div>
          )}
        </div>

        {/* Adherence Stats */}
        <div className="grid grid-cols-2 gap-3">
          <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
            <p style={{ color: colors.subtext, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.4px', marginBottom: 6 }}>This Week</p>
            <div style={{ color: colors.green, fontSize: 28, fontWeight: 700 }}>
              {protocolData.thisWeek.taken}/{protocolData.thisWeek.total}
            </div>
            <div style={{ color: colors.subtext, fontSize: 12, marginTop: 2 }}>
              {protocolData.thisWeek.adherence}% adherence
            </div>
          </div>
          <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
            <p style={{ color: colors.subtext, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.4px', marginBottom: 6 }}>All Time</p>
            <div style={{ color: colors.indigo, fontSize: 28, fontWeight: 700 }}>
              {protocolData.allTime.taken}/{protocolData.allTime.total}
            </div>
            <div style={{ color: colors.subtext, fontSize: 12, marginTop: 2 }}>
              {protocolData.allTime.adherence}% adherence
            </div>
          </div>
        </div>

        {/* Streak */}
        <div
          className="rounded-2xl p-4 flex items-center gap-3"
          style={{ backgroundColor: colors.card, border: `1px solid ${colors.orange}30` }}
        >
          <div
            className="w-12 h-12 rounded-xl flex items-center justify-center flex-shrink-0"
            style={{ backgroundColor: `${colors.orange}20` }}
          >
            <Flame size={24} color={colors.orange} />
          </div>
          <div className="flex-1">
            <div style={{ color: colors.text, fontSize: 22, fontWeight: 700 }}>
              {protocolData.streak} Day Streak
            </div>
            <div style={{ color: colors.subtext, fontSize: 12 }}>Keep it up — consistency is key</div>
          </div>
          <div className="text-right">
            <div style={{ color: colors.orange, fontSize: 13, fontWeight: 600 }}>Best: 14</div>
            <div style={{ color: colors.subtext, fontSize: 10 }}>days</div>
          </div>
        </div>

        {/* 21-Day Calendar Heatmap */}
        <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
          <p style={{ color: colors.subtext, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.4px', marginBottom: 12 }}>21-Day History</p>
          <AdherenceHeatmap history={protocolData.history} colors={colors} isDark={isDark} />
        </div>

        {/* Protocol Impact */}
        <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
          <div className="flex items-center gap-2 mb-3">
            <Zap size={14} color={colors.brand} />
            <p style={{ color: colors.subtext, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.4px' }}>Protocol Impact</p>
          </div>
          <div className="rounded-xl p-3 mb-3" style={{ backgroundColor: `${colors.green}12`, border: `1px solid ${colors.green}30` }}>
            <p style={{ color: colors.green, fontSize: 13, fontWeight: 600, marginBottom: 2 }}>
              +18% deeper sleep on sachet nights
            </p>
            <p style={{ color: colors.subtext, fontSize: 11 }}>
              Your data shows 135 min vs 105 min avg deep sleep when protocol is followed.
            </p>
          </div>
          <ImpactChart colors={colors} isDark={isDark} />
          <div className="flex gap-3 mt-2">
            <div className="flex items-center gap-1.5">
              <div style={{ width: 8, height: 8, borderRadius: 2, backgroundColor: colors.green }} />
              <span style={{ color: colors.subtext, fontSize: 10 }}>With sachet</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div style={{ width: 8, height: 8, borderRadius: 2, backgroundColor: isDark ? '#252545' : '#D1D1E0' }} />
              <span style={{ color: colors.subtext, fontSize: 10 }}>Without sachet</span>
            </div>
          </div>
        </div>

        {/* Ingredient List */}
        <div className="rounded-2xl overflow-hidden" style={{ backgroundColor: colors.card }}>
          <button
            onClick={() => setShowIngredients(s => !s)}
            className="w-full flex items-center justify-between p-4"
          >
            <div>
              <p style={{ color: colors.subtext, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.4px' }}>Formula Ingredients</p>
              <p style={{ color: colors.text, fontSize: 14, fontWeight: 600, marginTop: 1 }}>11 active compounds</p>
            </div>
            {showIngredients
              ? <ChevronUp size={16} color={colors.subtext} />
              : <ChevronDown size={16} color={colors.subtext} />}
          </button>

          <div style={{ maxHeight: showIngredients ? 600 : 0, overflow: 'hidden', transition: 'max-height 0.35s ease' }}>
            <div className="px-4 pb-4">
              {protocolData.ingredients.map((ing, i) => (
                <IngredientRow
                  key={ing.name}
                  {...ing}
                  colors={colors}
                  last={i === protocolData.ingredients.length - 1}
                />
              ))}
            </div>
          </div>
        </div>

      </div>
    </div>
  );
}
