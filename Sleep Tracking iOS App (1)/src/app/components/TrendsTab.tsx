import React, { useState } from 'react';
import {
  AreaChart, Area, BarChart, Bar, LineChart, Line,
  XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  ReferenceLine, Cell, ComposedChart,
} from 'recharts';
import { Zap, Brain, TrendingUp, TrendingDown, BarChart2, Activity, Clock, Minus } from 'lucide-react';
import { useTheme } from '../App';
import { ExpandableCard } from './ExpandableCard';
import { weeklyData, monthlyData, weekAvg, STAGE_COLORS } from '../data/sleepData';

type Range = '7D' | '30D';

// ── Shared Tooltip ────────────────────────────────────────────────────────────
function ChartTip({ active, payload, label, colors, unit = '', names }: any) {
  if (!active || !payload?.length) return null;
  return (
    <div style={{ backgroundColor: colors.card, borderRadius: 10, padding: '6px 10px', border: `1px solid ${colors.border}`, minWidth: 100 }}>
      <div style={{ color: colors.subtext, fontSize: 10, marginBottom: 3 }}>{label}</div>
      {payload.map((p: any, i: number) => (
        <div key={i} className="flex items-center gap-1.5" style={{ marginTop: 1 }}>
          <div style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: p.color }} />
          <span style={{ color: p.color, fontSize: 12, fontWeight: 600 }}>{typeof p.value === 'number' ? p.value.toFixed(1) : p.value}{unit}</span>
          {names?.[i] && <span style={{ color: colors.subtext, fontSize: 10 }}>{names[i]}</span>}
        </div>
      ))}
    </div>
  );
}

// ── Research Insight Card ─────────────────────────────────────────────────────
function InsightCard({ icon, color, title, body, colors, isDark }: {
  icon: React.ReactNode; color: string; title: string; body: string; colors: any; isDark: boolean;
}) {
  return (
    <div
      className="rounded-xl p-3 flex items-start gap-2.5"
      style={{ backgroundColor: `${color}10`, border: `1px solid ${color}25` }}
    >
      <div style={{ width: 26, height: 26, borderRadius: 7, backgroundColor: `${color}25`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, marginTop: 1 }}>
        {icon}
      </div>
      <div>
        <div style={{ color: colors.text, fontSize: 12, fontWeight: 600, marginBottom: 2 }}>{title}</div>
        <div style={{ color: colors.subtext, fontSize: 11 }}>{body}</div>
      </div>
    </div>
  );
}

// ── Sleep Score Area Chart ────────────────────────────────────────────────────
function ScoreChart({ range, colors, isDark }: { range: Range; colors: any; isDark: boolean }) {
  const data = range === '7D' ? weeklyData : monthlyData;
  return (
    <ResponsiveContainer width="100%" height={140}>
      <AreaChart data={data} margin={{ top: 8, right: 2, bottom: 0, left: -22 }}>
        <defs>
          <linearGradient id="scoreG" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%"   stopColor={colors.brand} stopOpacity={0.4} />
            <stop offset="100%" stopColor={colors.brand} stopOpacity={0}   />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" stroke={isDark ? '#1E1E36' : '#E0E0EE'} vertical={false} />
        <XAxis dataKey="day" tick={{ fill: colors.subtext, fontSize: 9 }} axisLine={false} tickLine={false} />
        <YAxis domain={[60, 100]} tick={{ fill: colors.subtext, fontSize: 9 }} axisLine={false} tickLine={false} />
        <ReferenceLine y={78} stroke={colors.subtext} strokeDasharray="4 2" strokeWidth={1} />
        <Tooltip content={<ChartTip colors={colors} unit="" names={['Score']} />} />
        <Area type="monotone" dataKey="score" stroke={colors.brand} strokeWidth={2} fill="url(#scoreG)"
          dot={{ r: 3, fill: colors.brand, strokeWidth: 0 }} activeDot={{ r: 4 }} />
      </AreaChart>
    </ResponsiveContainer>
  );
}

// ── Duration Bar Chart ────────────────────────────────────────────────────────
function DurationChart({ range, colors, isDark }: { range: Range; colors: any; isDark: boolean }) {
  const data = range === '7D' ? weeklyData : monthlyData;
  return (
    <ResponsiveContainer width="100%" height={140}>
      <BarChart data={data} margin={{ top: 8, right: 0, bottom: 0, left: -22 }} barCategoryGap="35%">
        <CartesianGrid strokeDasharray="3 3" stroke={isDark ? '#1E1E36' : '#E0E0EE'} vertical={false} />
        <XAxis dataKey="day" tick={{ fill: colors.subtext, fontSize: 9 }} axisLine={false} tickLine={false} />
        <YAxis domain={[0, 10]} tick={{ fill: colors.subtext, fontSize: 9 }} axisLine={false} tickLine={false} tickFormatter={v => `${v}h`} />
        <ReferenceLine y={8} stroke={colors.green} strokeDasharray="4 2" strokeWidth={1} label={{ value: '8h goal', fill: colors.green, fontSize: 9, position: 'right' }} />
        <Tooltip content={<ChartTip colors={colors} unit="h" names={['Hours']} />} />
        <Bar dataKey="hours" radius={[5, 5, 0, 0]}>
          {data.map((entry, i, arr) => (
            <Cell
              key={i}
              fill={i === arr.length - 1 ? colors.brand : entry.hours >= 8 ? colors.green : isDark ? '#1E1E3A' : '#D0D0E8'}
            />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}

// ── Stage Stacked Chart ───────────────────────────────────────────────────────
function StageChart({ range, colors, isDark }: { range: Range; colors: any; isDark: boolean }) {
  const data = range === '7D' ? weeklyData : monthlyData;
  return (
    <ResponsiveContainer width="100%" height={140}>
      <BarChart data={data} margin={{ top: 8, right: 0, bottom: 0, left: -22 }} barCategoryGap="35%">
        <CartesianGrid strokeDasharray="3 3" stroke={isDark ? '#1E1E36' : '#E0E0EE'} vertical={false} />
        <XAxis dataKey="day" tick={{ fill: colors.subtext, fontSize: 9 }} axisLine={false} tickLine={false} />
        <YAxis tick={{ fill: colors.subtext, fontSize: 9 }} axisLine={false} tickLine={false} tickFormatter={v => `${v}%`} />
        <Tooltip content={<ChartTip colors={colors} unit="%" />} />
        <Bar dataKey="deep"  stackId="a" fill={STAGE_COLORS.deep}  name="Deep"  />
        <Bar dataKey="core"  stackId="a" fill={STAGE_COLORS.core}  name="Core"  />
        <Bar dataKey="rem"   stackId="a" fill={STAGE_COLORS.rem}   name="REM"   />
        <Bar dataKey="awake" stackId="a" fill={STAGE_COLORS.awake} name="Awake" radius={[4,4,0,0]} />
      </BarChart>
    </ResponsiveContainer>
  );
}

// ── HRV Trend ─────────────────────────────────────────────────────────────────
function HRVChart({ range, colors, isDark }: { range: Range; colors: any; isDark: boolean }) {
  const data = range === '7D' ? weeklyData : monthlyData;
  return (
    <ResponsiveContainer width="100%" height={110}>
      <AreaChart data={data} margin={{ top: 8, right: 2, bottom: 0, left: -22 }}>
        <defs>
          <linearGradient id="hrvG" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%"   stopColor={colors.teal} stopOpacity={0.4} />
            <stop offset="100%" stopColor={colors.teal} stopOpacity={0}   />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" stroke={isDark ? '#1E1E36' : '#E0E0EE'} vertical={false} />
        <XAxis dataKey="day" tick={{ fill: colors.subtext, fontSize: 9 }} axisLine={false} tickLine={false} />
        <YAxis domain={[30, 65]} tick={{ fill: colors.subtext, fontSize: 9 }} axisLine={false} tickLine={false} />
        <Tooltip content={<ChartTip colors={colors} unit=" ms" names={['HRV']} />} />
        <Area type="monotone" dataKey="hrv" stroke={colors.teal} strokeWidth={2} fill="url(#hrvG)"
          dot={{ r: 3, fill: colors.teal, strokeWidth: 0 }} activeDot={{ r: 4 }} />
      </AreaChart>
    </ResponsiveContainer>
  );
}

// ── WASO & Latency Chart ──────────────────────────────────────────────────────
function WasoChart({ range, colors, isDark }: { range: Range; colors: any; isDark: boolean }) {
  const data = range === '7D' ? weeklyData : monthlyData;
  return (
    <ResponsiveContainer width="100%" height={120}>
      <ComposedChart data={data} margin={{ top: 8, right: 2, bottom: 0, left: -22 }} barCategoryGap="35%">
        <CartesianGrid strokeDasharray="3 3" stroke={isDark ? '#1E1E36' : '#E0E0EE'} vertical={false} />
        <XAxis dataKey="day" tick={{ fill: colors.subtext, fontSize: 9 }} axisLine={false} tickLine={false} />
        <YAxis tick={{ fill: colors.subtext, fontSize: 9 }} axisLine={false} tickLine={false} tickFormatter={v => `${v}m`} />
        <Tooltip content={<ChartTip colors={colors} unit=" min" />} />
        <Bar  dataKey="waso"    name="WASO"    fill={colors.orange} opacity={0.8} radius={[4,4,0,0]} />
        <Line dataKey="latency" name="Latency" stroke={colors.red}  strokeWidth={2} dot={{ r: 2.5, fill: colors.red, strokeWidth: 0 }} />
      </ComposedChart>
    </ResponsiveContainer>
  );
}

// ── Sleep Debt Chart ──────────────────────────────────────────────────────────
function SleepDebtChart({ colors, isDark }: { colors: any; isDark: boolean }) {
  // Running cumulative deficit vs 8h goal
  const data = weeklyData.map((d, i) => {
    const deficit = Math.max(0, 8 - d.hours);
    return { day: d.day, deficit: parseFloat(deficit.toFixed(2)) };
  });
  let running = 0;
  const cumulative = data.map(d => {
    running = Math.max(0, running + d.deficit);
    return { day: d.day, debt: parseFloat(running.toFixed(2)) };
  });

  return (
    <ResponsiveContainer width="100%" height={110}>
      <AreaChart data={cumulative} margin={{ top: 8, right: 2, bottom: 0, left: -22 }}>
        <defs>
          <linearGradient id="debtG" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%"   stopColor={colors.red} stopOpacity={0.4} />
            <stop offset="100%" stopColor={colors.red} stopOpacity={0}   />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" stroke={isDark ? '#1E1E36' : '#E0E0EE'} vertical={false} />
        <XAxis dataKey="day" tick={{ fill: colors.subtext, fontSize: 9 }} axisLine={false} tickLine={false} />
        <YAxis tick={{ fill: colors.subtext, fontSize: 9 }} axisLine={false} tickLine={false} tickFormatter={v => `${v}h`} />
        <Tooltip content={<ChartTip colors={colors} unit="h deficit" names={['Debt']} />} />
        <Area type="monotone" dataKey="debt" stroke={colors.red} strokeWidth={2} fill="url(#debtG)"
          dot={{ r: 3, fill: colors.red, strokeWidth: 0 }} activeDot={{ r: 4 }} />
      </AreaChart>
    </ResponsiveContainer>
  );
}

// ── Protocol Correlation Bars ─────────────────────────────────────────────────
function ProtocolCorrelation({ colors, isDark }: { colors: any; isDark: boolean }) {
  const data = [
    { metric: 'Deep\nSleep', with: 21, without: 14, unit: 'min' },
    { metric: 'REM\nSleep',  with: 24, without: 19, unit: '%' },
    { metric: 'Sleep\nScore',with: 85, without: 71, unit: '' },
    { metric: 'HRV',         with: 52, without: 39, unit: 'ms' },
    { metric: 'Efficiency',  with: 96, without: 88, unit: '%' },
  ];

  return (
    <div className="space-y-2 mt-2">
      {data.map(row => {
        const improvement = Math.round(((row.with - row.without) / row.without) * 100);
        return (
          <div key={row.metric}>
            <div className="flex justify-between items-center mb-1">
              <span style={{ color: colors.text, fontSize: 12 }}>{row.metric.replace('\n', ' ')}</span>
              <span style={{ color: colors.green, fontSize: 11, fontWeight: 600 }}>+{improvement}% with sachet</span>
            </div>
            <div className="relative" style={{ height: 10 }}>
              {/* Without bar */}
              <div className="absolute top-0 left-0 h-full rounded-full"
                style={{ width: `${(row.without / Math.max(row.with, row.without)) * 100}%`, backgroundColor: isDark ? '#1E1E3A' : '#D0D0E8', borderRadius: 4 }} />
              {/* With bar */}
              <div className="absolute top-0 left-0 h-full rounded-full"
                style={{ width: `${(row.with / Math.max(row.with, row.without) * 1) * 100}%`, backgroundColor: colors.green, opacity: 0.85, borderRadius: 4, maxWidth: '100%' }} />
            </div>
            <div className="flex justify-between mt-0.5">
              <span style={{ color: colors.subtext, fontSize: 9 }}>Without: {row.without}{row.unit}</span>
              <span style={{ color: colors.green, fontSize: 9 }}>With: {row.with}{row.unit}</span>
            </div>
          </div>
        );
      })}
      <div className="flex gap-4 pt-1">
        <div className="flex items-center gap-1.5">
          <div style={{ width: 8, height: 8, borderRadius: 2, backgroundColor: colors.green, opacity: 0.85 }} />
          <span style={{ color: colors.subtext, fontSize: 10 }}>With sachet</span>
        </div>
        <div className="flex items-center gap-1.5">
          <div style={{ width: 8, height: 8, borderRadius: 2, backgroundColor: isDark ? '#1E1E3A' : '#D0D0E8' }} />
          <span style={{ color: colors.subtext, fontSize: 10 }}>Without sachet</span>
        </div>
      </div>
    </div>
  );
}

// ── Summary Metrics Row ───────────────────────────────────────────────────────
function MetricPill({ label, value, delta, color, colors }: any) {
  const isPositive = delta?.startsWith('+');
  return (
    <div className="flex-1 rounded-xl p-3 text-center" style={{ backgroundColor: colors.card }}>
      <div style={{ color: colors.text, fontSize: 16, fontWeight: 700 }}>{value}</div>
      <div style={{ color: colors.subtext, fontSize: 10 }}>{label}</div>
      {delta && (
        <div style={{ color: isPositive ? colors.green : colors.orange, fontSize: 10, marginTop: 1 }}>{delta}</div>
      )}
    </div>
  );
}

// ── Main TrendsTab ────────────────────────────────────────────────────────────
export function TrendsTab() {
  const { isDark, colors } = useTheme();
  const [range, setRange] = useState<Range>('7D');

  const debt = weeklyData.reduce((acc, d) => acc + Math.max(0, 8 - d.hours), 0).toFixed(1);

  return (
    <div className="flex-1 overflow-y-auto" style={{ backgroundColor: colors.bg, scrollbarWidth: 'none' }}>

      {/* Header */}
      <div className="px-5 pt-3 pb-2 flex items-start justify-between">
        <div>
          <h1 style={{ color: colors.text, fontSize: 28, fontWeight: 700, letterSpacing: '-0.5px' }}>Insights</h1>
          <p style={{ color: colors.subtext, fontSize: 13, marginTop: 1 }}>Sleep science · research view</p>
        </div>
        {/* Range Picker */}
        <div className="flex rounded-xl overflow-hidden mt-1" style={{ backgroundColor: isDark ? '#1E1E36' : '#E0E0EE' }}>
          {(['7D', '30D'] as Range[]).map(r => (
            <button
              key={r}
              onClick={() => setRange(r)}
              style={{
                fontSize: 12, fontWeight: 600, paddingInline: 12, paddingBlock: 6,
                color: range === r ? '#fff' : colors.subtext,
                backgroundColor: range === r ? colors.brand : 'transparent',
                borderRadius: 8, transition: 'all 0.2s',
              }}
            >
              {r}
            </button>
          ))}
        </div>
      </div>

      <div className="px-4 pb-6 space-y-3">

        {/* Week Summary Pills */}
        <div className="flex gap-2">
          <MetricPill label="Avg Score"   value="81"       delta="+6 vs prev" color={colors.brand}  colors={colors} />
          <MetricPill label="Avg Sleep"   value="7h 31m"   delta="−17m to goal" color={colors.blue} colors={colors} />
          <MetricPill label="Sleep Debt"  value={`${debt}h`} delta="this week" color={colors.red}   colors={colors} />
        </div>

        {/* Research Insight Callouts */}
        <div className="space-y-2">
          <InsightCard
            icon={<Zap size={13} color={colors.green} />} color={colors.green}
            title="Protocol boost: +18% deep sleep on sachet nights"
            body="On nights you took your Better Sleep Formula (5 of 7 this week), your deep sleep averaged 21 min more and HRV was 13 ms higher."
            colors={colors} isDark={isDark}
          />
          <InsightCard
            icon={<TrendingUp size={13} color={colors.brand} />} color={colors.brand}
            title="30-day trajectory: sleep quality improving"
            body="Your average score increased from 68 → 82 over 30 days. Deep sleep improved +8 percentage points. Consistency score: 80%."
            colors={colors} isDark={isDark}
          />
          <InsightCard
            icon={<Clock size={13} color={colors.orange} />} color={colors.orange}
            title="Bed time matters: earlier = deeper"
            body="On nights you went to bed before 11:30 PM, deep sleep was 24 min longer on average. Your latest night (12:35 AM) had the lowest score (70)."
            colors={colors} isDark={isDark}
          />
        </div>

        {/* Sleep Score */}
        <ExpandableCard
          title="Sleep Quality Score"
          icon={<TrendingUp size={15} color="#fff" />}
          iconBg={colors.brand}
          defaultExpanded
          summary={<span style={{ color: colors.text, fontSize: 15, fontWeight: 600 }}>81 avg · ↑ improving</span>}
        >
          <ScoreChart range={range} colors={colors} isDark={isDark} />
          <div className="flex justify-between mt-3">
            {[
              { label: 'Best',   value: '90', color: colors.green },
              { label: 'Avg',    value: '81', color: colors.brand },
              { label: 'Worst',  value: '70', color: colors.orange },
              { label: 'Baseline', value: '78', color: colors.subtext },
            ].map(s => (
              <div key={s.label} className="text-center">
                <div style={{ color: s.color, fontSize: 16, fontWeight: 700 }}>{s.value}</div>
                <div style={{ color: colors.subtext, fontSize: 9 }}>{s.label}</div>
              </div>
            ))}
          </div>
        </ExpandableCard>

        {/* Sleep Duration */}
        <ExpandableCard
          title="Sleep Duration"
          icon={<BarChart2 size={15} color="#fff" />}
          iconBg={colors.indigo}
          summary={<span style={{ color: colors.text, fontSize: 15, fontWeight: 600 }}>7h 31m avg · 5/7 met goal</span>}
        >
          <DurationChart range={range} colors={colors} isDark={isDark} />
          <div className="mt-2 rounded-xl p-2.5" style={{ backgroundColor: `${colors.orange}10`, border: `1px solid ${colors.orange}25` }}>
            <span style={{ color: colors.orange, fontSize: 12 }}>⚠ Sleep debt: <strong>{debt}h</strong> accumulated this week. Aim for 8h+ tonight.</span>
          </div>
        </ExpandableCard>

        {/* Sleep Architecture */}
        <ExpandableCard
          title="Sleep Architecture"
          icon={<Activity size={15} color="#fff" />}
          iconBg={colors.purple}
          summary={<span style={{ color: colors.subtext, fontSize: 12 }}>Deep · Core · REM · Awake distribution</span>}
        >
          <StageChart range={range} colors={colors} isDark={isDark} />
          <div className="flex gap-3 mt-2 flex-wrap">
            {(['deep','core','rem','awake'] as const).map(k => (
              <div key={k} className="flex items-center gap-1">
                <div style={{ width: 8, height: 8, borderRadius: 2, backgroundColor: STAGE_COLORS[k] }} />
                <span style={{ color: colors.subtext, fontSize: 10, textTransform: 'capitalize' }}>{k}</span>
              </div>
            ))}
          </div>
          <div className="mt-3 space-y-1.5">
            {[
              { label: 'Deep Sleep',  avg: '20%', trend: '↑ +5% vs baseline', tcolor: colors.green  },
              { label: 'REM Sleep',   avg: '23%', trend: '→ within baseline',  tcolor: colors.subtext },
              { label: 'Core Sleep',  avg: '51%', trend: '→ stable',           tcolor: colors.subtext },
              { label: 'Awake/WASO',  avg: '6%',  trend: '↓ −1% improving',   tcolor: colors.green  },
            ].map(row => (
              <div key={row.label} className="flex justify-between items-center">
                <span style={{ color: colors.text, fontSize: 12 }}>{row.label}</span>
                <div className="flex items-center gap-3">
                  <span style={{ color: row.tcolor, fontSize: 11 }}>{row.trend}</span>
                  <span style={{ color: colors.text, fontSize: 13, fontWeight: 600 }}>{row.avg}</span>
                </div>
              </div>
            ))}
          </div>
        </ExpandableCard>

        {/* Protocol Impact */}
        <ExpandableCard
          title="Protocol Impact Analysis"
          icon={<Zap size={15} color="#fff" />}
          iconBg={colors.green}
          summary={<span style={{ color: colors.green, fontSize: 14, fontWeight: 600 }}>Sachet nights score 20% higher</span>}
        >
          <div className="rounded-xl p-3 mb-3" style={{ backgroundColor: `${colors.green}10`, border: `1px solid ${colors.green}25` }}>
            <div style={{ color: colors.text, fontSize: 13, fontWeight: 600, marginBottom: 3 }}>Based on your last 21 nights</div>
            <div className="grid grid-cols-3 gap-2">
              {[
                { label: 'Sachet nights', value: '19', color: colors.green },
                { label: 'Missed nights', value: '2',  color: colors.orange },
                { label: 'Adherence',     value: '90%', color: colors.brand },
              ].map(s => (
                <div key={s.label} className="text-center">
                  <div style={{ color: s.color, fontSize: 16, fontWeight: 700 }}>{s.value}</div>
                  <div style={{ color: colors.subtext, fontSize: 9 }}>{s.label}</div>
                </div>
              ))}
            </div>
          </div>
          <ProtocolCorrelation colors={colors} isDark={isDark} />
        </ExpandableCard>

        {/* HRV Trend */}
        <ExpandableCard
          title="Heart Rate Variability"
          icon={<Activity size={15} color="#fff" />}
          iconBg={colors.teal}
          summary={
            <div className="flex items-baseline gap-1">
              <span style={{ color: colors.text, fontSize: 18, fontWeight: 700 }}>52ms</span>
              <span style={{ color: colors.green, fontSize: 13 }}>↑ +13ms vs 30-day avg</span>
            </div>
          }
        >
          <HRVChart range={range} colors={colors} isDark={isDark} />
          <div className="mt-3 rounded-xl p-3" style={{ backgroundColor: `${colors.teal}10`, border: `1px solid ${colors.teal}25` }}>
            <div style={{ color: colors.text, fontSize: 12, fontWeight: 600 }}>What HRV tells us</div>
            <div style={{ color: colors.subtext, fontSize: 11, marginTop: 2 }}>
              Higher HRV indicates better autonomic nervous system recovery. Your HRV has improved from 36 ms → 52 ms over 30 days, correlating with protocol adherence.
            </div>
          </div>
          <div className="flex justify-between mt-3">
            {[
              { label: 'Tonight', value: '52ms', color: colors.teal },
              { label: '7D Avg',  value: '49ms', color: colors.brand },
              { label: '30D Avg', value: '42ms', color: colors.subtext },
            ].map(s => (
              <div key={s.label} className="text-center">
                <div style={{ color: s.color, fontSize: 15, fontWeight: 700 }}>{s.value}</div>
                <div style={{ color: colors.subtext, fontSize: 9 }}>{s.label}</div>
              </div>
            ))}
          </div>
        </ExpandableCard>

        {/* WASO & Latency */}
        <ExpandableCard
          title="WASO & Sleep Latency"
          icon={<Clock size={15} color="#fff" />}
          iconBg={colors.orange}
          summary={
            <div className="flex gap-3">
              <span style={{ color: colors.text, fontSize: 14, fontWeight: 600 }}>WASO 23m</span>
              <span style={{ color: colors.text, fontSize: 14, fontWeight: 600 }}>·</span>
              <span style={{ color: colors.text, fontSize: 14, fontWeight: 600 }}>Latency 11m</span>
            </div>
          }
        >
          <WasoChart range={range} colors={colors} isDark={isDark} />
          <div className="flex gap-2 mt-2">
            <div className="flex items-center gap-1.5">
              <div style={{ width: 8, height: 8, borderRadius: 2, backgroundColor: colors.orange }} />
              <span style={{ color: colors.subtext, fontSize: 10 }}>WASO (wake after sleep onset)</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div style={{ width: 8, height: 2, backgroundColor: colors.red }} />
              <span style={{ color: colors.subtext, fontSize: 10 }}>Latency</span>
            </div>
          </div>
          <div className="mt-3 grid grid-cols-2 gap-2">
            {[
              { label: 'Avg WASO',    tonight: '23m', avg: '31m', better: true },
              { label: 'Avg Latency', tonight: '11m', avg: '16m', better: true },
            ].map(row => (
              <div key={row.label} className="rounded-xl p-2.5" style={{ backgroundColor: colors.card2 }}>
                <div style={{ color: colors.subtext, fontSize: 10, marginBottom: 2 }}>{row.label}</div>
                <div style={{ color: row.better ? colors.green : colors.orange, fontSize: 15, fontWeight: 700 }}>{row.tonight}</div>
                <div style={{ color: colors.subtext, fontSize: 10 }}>avg {row.avg}</div>
              </div>
            ))}
          </div>
        </ExpandableCard>

        {/* Sleep Debt */}
        <ExpandableCard
          title="Sleep Debt Tracker"
          icon={<TrendingDown size={15} color="#fff" />}
          iconBg={colors.red}
          summary={
            <div className="flex items-baseline gap-1">
              <span style={{ color: colors.red, fontSize: 18, fontWeight: 700 }}>{debt}h</span>
              <span style={{ color: colors.subtext, fontSize: 12 }}>deficit this week</span>
            </div>
          }
        >
          <SleepDebtChart colors={colors} isDark={isDark} />
          <div className="mt-3 rounded-xl p-3" style={{ backgroundColor: `${colors.red}10`, border: `1px solid ${colors.red}25` }}>
            <div style={{ color: colors.red, fontSize: 13, fontWeight: 600, marginBottom: 2 }}>Sleep debt accumulation</div>
            <div style={{ color: colors.subtext, fontSize: 11 }}>
              You're {debt}h short of your 8h goal this week. Two nights (Fri 6.5h, Mon 6.75h) drove most of the deficit. Prioritise 8.5h+ over the weekend to recover.
            </div>
          </div>
        </ExpandableCard>

        {/* Deep Research Insights */}
        <div className="rounded-2xl p-4" style={{ backgroundColor: colors.card }}>
          <div className="flex items-center gap-2 mb-3">
            <Brain size={14} color={colors.brand} />
            <p style={{ color: colors.subtext, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.4px' }}>Research Insights</p>
          </div>
          <div className="space-y-2.5">
            {[
              {
                icon: '🌙', color: colors.indigo,
                title: 'Your optimal sleep window',
                body: 'Nights with bed time 11:00–11:30 PM produce 24 min more deep sleep. Aim to be in bed by 11:15 PM.',
              },
              {
                icon: '💊', color: colors.green,
                title: 'Sachet timing matters',
                body: 'Taking your sachet 45–60 min before bed (vs 30 min) correlates with 12 min more deep sleep on average.',
              },
              {
                icon: '📱', color: colors.orange,
                title: 'Screen time impact',
                body: 'On nights you logged highest screen activity, sleep latency averaged 22 min vs 9 min on low-screen nights.',
              },
              {
                icon: '🏃', color: colors.teal,
                title: 'Activity & recovery',
                body: 'Your HRV is 8 ms higher on days following 30+ min of exercise, suggesting exercise supports protocol effectiveness.',
              },
            ].map(insight => (
              <div
                key={insight.title}
                className="flex items-start gap-3 p-3 rounded-xl"
                style={{ backgroundColor: `${insight.color}10`, border: `1px solid ${insight.color}20` }}
              >
                <span style={{ fontSize: 18, flexShrink: 0 }}>{insight.icon}</span>
                <div>
                  <div style={{ color: colors.text, fontSize: 12, fontWeight: 600, marginBottom: 2 }}>{insight.title}</div>
                  <div style={{ color: colors.subtext, fontSize: 11 }}>{insight.body}</div>
                </div>
              </div>
            ))}
          </div>
        </div>

      </div>
    </div>
  );
}