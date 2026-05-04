// ── Better Sleep · Mock Data ───────────────────────────────────────────────────

export const STAGE_COLORS = {
  deep:  '#2D2DBF',
  core:  '#5E5CE6',
  rem:   '#5AC8FA',
  awake: '#FF9F0A',
} as const;

// Apple Health simplified stage colors (for the new chart)
export const AH_STAGE = {
  deep:  { bg: '#2D2DBF', label: 'Deep',  rise: 14 },  // barely rises = deepest
  core:  { bg: '#5E5CE6', label: 'Core',  rise: 36 },
  rem:   { bg: '#5AC8FA', label: 'REM',   rise: 56 },
  awake: { bg: '#FF9F0A', label: 'Awake', rise: 88 },  // tallest = awake
} as const;

export type Stage = keyof typeof STAGE_COLORS;

// Tonight's sleep blocks (minutes from 11:32 PM = 0)
export const todayBlocks: { start: number; duration: number; stage: Stage }[] = [
  { start: 0,   duration: 13,  stage: 'core'  },
  { start: 13,  duration: 75,  stage: 'deep'  },
  { start: 88,  duration: 45,  stage: 'core'  },
  { start: 133, duration: 45,  stage: 'rem'   },
  { start: 178, duration: 15,  stage: 'awake' },
  { start: 193, duration: 30,  stage: 'core'  },
  { start: 223, duration: 60,  stage: 'deep'  },
  { start: 283, duration: 45,  stage: 'core'  },
  { start: 328, duration: 75,  stage: 'rem'   },
  { start: 403, duration: 30,  stage: 'core'  },
  { start: 433, duration: 25,  stage: 'rem'   },
  { start: 458, duration: 8,   stage: 'awake' },
];
export const TOTAL_MINUTES = 466;

// ── Per-day sleep records (last 7 days, index 0 = 6 days ago, 6 = tonight) ──
export const dailySleepData = [
  {
    date: 'Mon, Apr 28', bedTime: '12:10 AM', wakeTime: '6:55 AM',
    timeAsleep: { hours: 6, minutes: 45 }, timeInBed: { hours: 6, minutes: 55 },
    efficiency: 87, score: 74, latency: 18, waso: 35, hrv: 41,
    respiratoryRate: 13.8,
    stages: { deep: { minutes: 96,  percentage: 15 }, core: { minutes: 245, percentage: 57 }, rem: { minutes: 145, percentage: 22 }, awake: { minutes: 35, percentage: 6 } },
    blocks: [
      { start: 0, duration: 20, stage: 'core' as Stage }, { start: 20, duration: 50, stage: 'deep' as Stage },
      { start: 70, duration: 30, stage: 'core' as Stage }, { start: 100, duration: 45, stage: 'rem' as Stage },
      { start: 145, duration: 20, stage: 'awake' as Stage }, { start: 165, duration: 40, stage: 'core' as Stage },
      { start: 205, duration: 46, stage: 'deep' as Stage }, { start: 251, duration: 55, stage: 'core' as Stage },
      { start: 306, duration: 55, stage: 'rem' as Stage }, { start: 361, duration: 30, stage: 'core' as Stage },
      { start: 391, duration: 15, stage: 'awake' as Stage },
    ],
  },
  {
    date: 'Tue, Apr 29', bedTime: '11:45 PM', wakeTime: '7:05 AM',
    timeAsleep: { hours: 7, minutes: 20 }, timeInBed: { hours: 7, minutes: 35 },
    efficiency: 91, score: 80, latency: 13, waso: 24, hrv: 48,
    respiratoryRate: 14.1,
    stages: { deep: { minutes: 124, percentage: 19 }, core: { minutes: 245, percentage: 54 }, rem: { minutes: 152, percentage: 21 }, awake: { minutes: 24, percentage: 6 } },
    blocks: [
      { start: 0, duration: 15, stage: 'core' as Stage }, { start: 15, duration: 60, stage: 'deep' as Stage },
      { start: 75, duration: 40, stage: 'core' as Stage }, { start: 115, duration: 50, stage: 'rem' as Stage },
      { start: 165, duration: 12, stage: 'awake' as Stage }, { start: 177, duration: 35, stage: 'core' as Stage },
      { start: 212, duration: 64, stage: 'deep' as Stage }, { start: 276, duration: 50, stage: 'core' as Stage },
      { start: 326, duration: 52, stage: 'rem' as Stage }, { start: 378, duration: 50, stage: 'core' as Stage },
      { start: 428, duration: 12, stage: 'awake' as Stage },
    ],
  },
  {
    date: 'Wed, Apr 30', bedTime: '11:10 PM', wakeTime: '7:20 AM',
    timeAsleep: { hours: 8, minutes: 10 }, timeInBed: { hours: 8, minutes: 20 },
    efficiency: 96, score: 88, latency: 9, waso: 14, hrv: 55,
    respiratoryRate: 13.5,
    stages: { deep: { minutes: 152, percentage: 22 }, core: { minutes: 240, percentage: 47 }, rem: { minutes: 175, percentage: 25 }, awake: { minutes: 14, percentage: 6 } },
    blocks: [
      { start: 0, duration: 10, stage: 'core' as Stage }, { start: 10, duration: 85, stage: 'deep' as Stage },
      { start: 95, duration: 45, stage: 'core' as Stage }, { start: 140, duration: 60, stage: 'rem' as Stage },
      { start: 200, duration: 8, stage: 'awake' as Stage }, { start: 208, duration: 35, stage: 'core' as Stage },
      { start: 243, duration: 67, stage: 'deep' as Stage }, { start: 310, duration: 50, stage: 'core' as Stage },
      { start: 360, duration: 60, stage: 'rem' as Stage }, { start: 420, duration: 50, stage: 'core' as Stage },
      { start: 470, duration: 6, stage: 'awake' as Stage },
    ],
  },
  {
    date: 'Thu, May 1', bedTime: '11:30 PM', wakeTime: '7:15 AM',
    timeAsleep: { hours: 7, minutes: 45 }, timeInBed: { hours: 7, minutes: 55 },
    efficiency: 93, score: 85, latency: 11, waso: 18, hrv: 52,
    respiratoryRate: 14.0,
    stages: { deep: { minutes: 135, percentage: 20 }, core: { minutes: 243, percentage: 50 }, rem: { minutes: 163, percentage: 24 }, awake: { minutes: 24, percentage: 6 } },
    blocks: [
      { start: 0, duration: 12, stage: 'core' as Stage }, { start: 12, duration: 72, stage: 'deep' as Stage },
      { start: 84, duration: 42, stage: 'core' as Stage }, { start: 126, duration: 48, stage: 'rem' as Stage },
      { start: 174, duration: 10, stage: 'awake' as Stage }, { start: 184, duration: 32, stage: 'core' as Stage },
      { start: 216, duration: 63, stage: 'deep' as Stage }, { start: 279, duration: 48, stage: 'core' as Stage },
      { start: 327, duration: 70, stage: 'rem' as Stage }, { start: 397, duration: 48, stage: 'core' as Stage },
      { start: 445, duration: 14, stage: 'awake' as Stage },
    ],
  },
  {
    date: 'Fri, May 2', bedTime: '12:35 AM', wakeTime: '7:05 AM',
    timeAsleep: { hours: 6, minutes: 30 }, timeInBed: { hours: 6, minutes: 45 },
    efficiency: 84, score: 70, latency: 22, waso: 42, hrv: 38,
    respiratoryRate: 14.6,
    stages: { deep: { minutes: 91, percentage: 14 }, core: { minutes: 260, percentage: 60 }, rem: { minutes: 130, percentage: 19 }, awake: { minutes: 42, percentage: 7 } },
    blocks: [
      { start: 0, duration: 25, stage: 'core' as Stage }, { start: 25, duration: 40, stage: 'deep' as Stage },
      { start: 65, duration: 55, stage: 'core' as Stage }, { start: 120, duration: 40, stage: 'rem' as Stage },
      { start: 160, duration: 28, stage: 'awake' as Stage }, { start: 188, duration: 45, stage: 'core' as Stage },
      { start: 233, duration: 51, stage: 'deep' as Stage }, { start: 284, duration: 60, stage: 'core' as Stage },
      { start: 344, duration: 50, stage: 'rem' as Stage }, { start: 394, duration: 50, stage: 'core' as Stage },
      { start: 444, duration: 14, stage: 'awake' as Stage },
    ],
  },
  {
    date: 'Sat, May 3', bedTime: '11:00 PM', wakeTime: '7:45 AM',
    timeAsleep: { hours: 8, minutes: 45 }, timeInBed: { hours: 8, minutes: 55 },
    efficiency: 97, score: 90, latency: 8, waso: 11, hrv: 58,
    respiratoryRate: 13.2,
    stages: { deep: { minutes: 158, percentage: 23 }, core: { minutes: 230, percentage: 44 }, rem: { minutes: 183, percentage: 26 }, awake: { minutes: 34, percentage: 7 } },
    blocks: [
      { start: 0, duration: 10, stage: 'core' as Stage }, { start: 10, duration: 90, stage: 'deep' as Stage },
      { start: 100, duration: 45, stage: 'core' as Stage }, { start: 145, duration: 65, stage: 'rem' as Stage },
      { start: 210, duration: 6, stage: 'awake' as Stage }, { start: 216, duration: 35, stage: 'core' as Stage },
      { start: 251, duration: 68, stage: 'deep' as Stage }, { start: 319, duration: 50, stage: 'core' as Stage },
      { start: 369, duration: 65, stage: 'rem' as Stage }, { start: 434, duration: 50, stage: 'core' as Stage },
      { start: 484, duration: 5, stage: 'awake' as Stage },
    ],
  },
  {
    date: 'Sun, May 4', bedTime: '11:32 PM', wakeTime: '7:18 AM',
    timeAsleep: { hours: 7, minutes: 23 }, timeInBed: { hours: 7, minutes: 46 },
    efficiency: 97, score: 82, latency: 11, waso: 23, hrv: 52,
    respiratoryRate: 14.2,
    stages: { deep: { minutes: 135, percentage: 21 }, core: { minutes: 233, percentage: 51 }, rem: { minutes: 145, percentage: 23 }, awake: { minutes: 23, percentage: 5 } },
    blocks: todayBlocks,
  },
];
// TOTAL_MINUTES already exported above — removed duplicate

export const todaySleep = dailySleepData[6];
export const averageSleep = {
  label: '30-Day Avg',
  timeAsleep: { hours: 7, minutes: 45 },
  score: 78, latency: 16, waso: 31, hrv: 46,
  stages: {
    deep:  { minutes: 126, percentage: 18 },
    core:  { minutes: 237, percentage: 52 },
    rem:   { minutes: 158, percentage: 25 },
    awake: { minutes: 37,  percentage: 7  },
  },
};

// Heart rate during sleep (every 30 min)
export const heartRateData = [
  { time: '11:30', bpm: 68 }, { time: '12:00', bpm: 62 },
  { time: '12:30', bpm: 55 }, { time: '1:00',  bpm: 52 },
  { time: '1:30',  bpm: 48 }, { time: '2:00',  bpm: 51 },
  { time: '2:30',  bpm: 71 }, { time: '3:00',  bpm: 57 },
  { time: '3:30',  bpm: 49 }, { time: '4:00',  bpm: 46 },
  { time: '4:30',  bpm: 50 }, { time: '5:00',  bpm: 56 },
  { time: '5:30',  bpm: 61 }, { time: '6:00',  bpm: 64 },
  { time: '6:30',  bpm: 66 }, { time: '7:00',  bpm: 69 },
  { time: '7:30',  bpm: 72 },
];

// Weekly 7-day data (for Insights charts)
export const weeklyData = [
  { day: 'Mon', date: 'Apr 28', hours: 6.75, score: 74, deep: 15, core: 57, rem: 22, awake: 6, hrv: 41, waso: 35, latency: 18, taken: true,  bed: '12:10', wake: '6:55' },
  { day: 'Tue', date: 'Apr 29', hours: 7.33, score: 80, deep: 19, core: 54, rem: 21, awake: 6, hrv: 48, waso: 24, latency: 13, taken: true,  bed: '11:45', wake: '7:05' },
  { day: 'Wed', date: 'Apr 30', hours: 8.17, score: 88, deep: 22, core: 47, rem: 25, awake: 6, hrv: 55, waso: 14, latency: 9,  taken: true,  bed: '11:10', wake: '7:20' },
  { day: 'Thu', date: 'May 1',  hours: 7.75, score: 85, deep: 20, core: 50, rem: 24, awake: 6, hrv: 52, waso: 18, latency: 11, taken: false, bed: '11:30', wake: '7:15' },
  { day: 'Fri', date: 'May 2',  hours: 6.50, score: 70, deep: 14, core: 60, rem: 19, awake: 7, hrv: 38, waso: 42, latency: 22, taken: false, bed: '12:35', wake: '7:05' },
  { day: 'Sat', date: 'May 3',  hours: 8.75, score: 90, deep: 23, core: 44, rem: 26, awake: 7, hrv: 58, waso: 11, latency: 8,  taken: true,  bed: '11:00', wake: '7:45' },
  { day: 'Sun', date: 'May 4',  hours: 7.38, score: 82, deep: 21, core: 51, rem: 23, awake: 5, hrv: 52, waso: 23, latency: 11, taken: true,  bed: '11:32', wake: '7:18' },
];

export const monthlyData = [
  { week: 'W1 Apr 7',  day: 'W1', hours: 6.4, score: 68, deep: 13, core: 57, rem: 22, awake: 8, hrv: 36, waso: 44, latency: 25, taken: 4 },
  { week: 'W2 Apr 14', day: 'W2', hours: 6.9, score: 72, deep: 16, core: 55, rem: 22, awake: 7, hrv: 40, waso: 36, latency: 20, taken: 5 },
  { week: 'W3 Apr 21', day: 'W3', hours: 7.2, score: 76, deep: 18, core: 53, rem: 23, awake: 6, hrv: 44, waso: 30, latency: 16, taken: 6 },
  { week: 'W4 Apr 28', day: 'W4', hours: 7.5, score: 81, deep: 21, core: 51, rem: 22, awake: 6, hrv: 49, waso: 24, latency: 12, taken: 5 },
];
export const weekAvg = { hours: 7.52, score: 81.3 };

// ── Biology Data ─────────────────────────────────────────────────────────────
export const biologyData = {
  vo2Max:        { value: 47.0, rating: 'Fair',         trend: 'Stable',      history: [44.2, 45.0, 45.8, 46.2, 46.5, 46.8, 47.0] },
  hrv:           { value: 83.0, rating: 'Stabilizing',  trend: 'Improving',   history: [68, 71, 74, 76, 79, 81, 83] },
  rhr:           { value: 60.1, rating: 'Fair',         trend: 'Stable',      history: [64, 63, 62, 61, 61, 60, 60] },
  weight:        { value: 76.3, unit: 'kg',  rating: 'Increasing', trend: 'Increasing', history: [75.1, 75.4, 75.6, 75.8, 76.0, 76.2, 76.3] },
  leanBodyMass:  { value: 62.3, unit: 'kg',  rating: 'No trend',   trend: 'Stable',      history: [61.8, 61.9, 62.0, 62.1, 62.2, 62.2, 62.3] },
  bodyFat:       { value: 18.5, unit: '%',   rating: 'Acceptable', trend: 'Stable',      history: [19.2, 19.0, 18.9, 18.8, 18.7, 18.6, 18.5] },
  bloodOxygen:   { value: 98,   unit: '%',   rating: 'Good',       trend: 'Normal',      history: [97, 98, 97, 98, 98, 97, 98] },
  temperature:   { value: 36.6, unit: '°C',  rating: 'Normal',     trend: 'Stable',      history: [36.4, 36.5, 36.5, 36.6, 36.6, 36.7, 36.6] },
};

// ── Protocol Data ─────────────────────────────────────────────────────────────
export const protocolData = {
  dayNumber: 21, streak: 12, takenTonight: true, takenAt: '9:45 PM',
  thisWeek:  { taken: 6,  total: 7,  adherence: 86 },
  allTime:   { taken: 19, total: 21, adherence: 90 },
  adherenceScore: 90,
  history: [true,true,false,true,true,true,true,true,false,true,true,true,true,true,true,true,false,true,true,true,true],
  ingredients: [
    { name: 'Magnesium Glycinate', dose: '200mg', benefit: 'Muscle relaxation & recovery', color: '#7C3AED' },
    { name: 'L-Theanine',          dose: '100mg', benefit: 'Calm focus without drowsiness', color: '#2DD4BF' },
    { name: 'Ashwagandha',         dose: '300mg', benefit: 'Cortisol & stress reduction',  color: '#F59E0B' },
    { name: 'Passionflower',       dose: '250mg', benefit: 'Natural sedative properties',  color: '#EC4899' },
    { name: 'Valerian Root',       dose: '200mg', benefit: 'Sleep onset & depth',          color: '#10B981' },
    { name: '5-HTP',               dose: '50mg',  benefit: 'Serotonin & REM precursor',   color: '#3B82F6' },
    { name: 'Melatonin',           dose: '0.5mg', benefit: 'Circadian rhythm sync',        color: '#8B5CF6' },
    { name: 'GABA',                dose: '100mg', benefit: 'CNS calming effect',           color: '#06B6D4' },
    { name: 'Lemon Balm',          dose: '150mg', benefit: 'Anxiety & sleep quality',      color: '#84CC16' },
    { name: 'Chamomile',           dose: '200mg', benefit: 'Duration & calm',              color: '#F97316' },
    { name: 'Vitamin B6',          dose: '2mg',   benefit: 'Dream recall & REM support',   color: '#EF4444' },
  ],
  correlationData: {
    withSachet:    { deepSleep: 21, rem: 24, score: 85, efficiency: 96, hrv: 52 },
    withoutSachet: { deepSleep: 14, rem: 19, score: 71, efficiency: 88, hrv: 39 },
  },
};

// ── Alerts Data ───────────────────────────────────────────────────────────────
export const recentNotifications = [
  { id: 1, type: 'sachet',   icon: '💊', title: 'Sachet Reminder',       body: 'Time to take your Better Sleep Formula',         time: '9:00 PM', date: 'Today',    read: false },
  { id: 2, type: 'analysis', icon: '🌙', title: 'Sleep Analysis Ready',  body: 'Score 82 · 7h 23m · Good — tap to view details', time: '8:15 AM', date: 'Today',    read: false },
  { id: 3, type: 'insight',  icon: '📊', title: 'New Insight Available', body: 'Your deep sleep improved +18% this week',        time: '8:00 AM', date: 'Today',    read: true  },
  { id: 4, type: 'report',   icon: '📈', title: 'Weekly Sleep Report',   body: 'Avg score 81 · Best night 90 · Streak 12 days',  time: '8:00 AM', date: 'Sun May 3',read: true  },
  { id: 5, type: 'alert',    icon: '⚠️', title: 'Low Sleep Score',       body: 'Score 70 · Sleep debt may be accumulating',       time: '8:20 AM', date: 'Fri May 2',read: true  },
];

// ── Helpers ───────────────────────────────────────────────────────────────────
export function minutesToHM(min: number): string {
  const h = Math.floor(min / 60);
  const m = min % 60;
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}
export function minutesToHMS(min: number): string {
  const h = Math.floor(min / 60);
  const m = min % 60;
  return `${h}:${m.toString().padStart(2,'0')}:00`;
}
export function formatDuration(hours: number, minutes: number): string {
  return `${hours}h ${minutes}m`;
}