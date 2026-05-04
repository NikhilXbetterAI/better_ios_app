import React, {
  createContext,
  useContext,
  useState,
} from "react";
import { IPhoneFrame } from "./components/IPhoneFrame";
import { TabBar } from "./components/TabBar";
import { SleepTab } from "./components/SleepTab";
import { TrendsTab } from "./components/TrendsTab";
import { ProtocolTab } from "./components/ProtocolTab";
import { BiologyTab } from "./components/BiologyTab";
import { ActivityTab } from "./components/ActivityTab";
import { Sun, Moon } from "lucide-react";

export type Tab =
  | "sleep"
  | "trends"
  | "protocol"
  | "biology"
  | "activity";

// ── Better Sleep Brand Palette ────────────────────────────────────────────────
export const DARK_COLORS = {
  bg: "#080812",
  card: "#11112A",
  card2: "#191932",
  card3: "#22224A",
  text: "#FFFFFF",
  subtext: "#8E8E9A",
  border: "#222240",
  blue: "#0A84FF",
  green: "#30D158",
  orange: "#FF9F0A",
  purple: "#BF5AF2",
  red: "#FF453A",
  indigo: "#6366F1",
  teal: "#2DD4BF",
  cyan: "#64D2FF",
  brand: "#6366F1",
  violet: "#8B5CF6",
};

export const LIGHT_COLORS = {
  bg: "#EFEFF8",
  card: "#FFFFFF",
  card2: "#E8E8F4",
  card3: "#DDDDF0",
  text: "#0A0A20",
  subtext: "#6B7280",
  border: "#E0E0F0",
  blue: "#007AFF",
  green: "#34C759",
  orange: "#FF9500",
  purple: "#AF52DE",
  red: "#FF3B30",
  indigo: "#5856D6",
  teal: "#14B8A6",
  cyan: "#32ADE6",
  brand: "#5856D6",
  violet: "#7C3AED",
};

// ── Theme Context ─────────────────────────────────────────────────────────────
interface ThemeCtx {
  isDark: boolean;
  toggleTheme: () => void;
  colors: typeof DARK_COLORS;
  activeTab: Tab;
  setActiveTab: (t: Tab) => void;
}

const ThemeContext = createContext<ThemeCtx>({
  isDark: true,
  toggleTheme: () => {},
  colors: DARK_COLORS,
  activeTab: "sleep",
  setActiveTab: () => {},
});

export function useTheme() {
  return useContext(ThemeContext);
}

// ── App ───────────────────────────────────────────────────────────────────────
export default function App() {
  const [isDark, setIsDark] = useState(true);
  const [activeTab, setActiveTab] = useState<Tab>("sleep");
  const colors = isDark ? DARK_COLORS : LIGHT_COLORS;

  return (
    <ThemeContext.Provider
      value={{
        isDark,
        toggleTheme: () => setIsDark((p) => !p),
        colors,
        activeTab,
        setActiveTab,
      }}
    >
      <div
        className="min-h-screen w-full flex items-center justify-center"
        style={{
          background: isDark
            ? "radial-gradient(ellipse at 25% 15%, #1a103a 0%, #080812 55%, #000 100%)"
            : "radial-gradient(ellipse at 25% 15%, #dddaf5 0%, #efeff8 55%, #e8e8f4 100%)",
          transition: "background 0.4s",
          padding: "20px 16px",
          minHeight: "100vh",
          minWidth: "100vw",
        }}
      >
        <div className="flex flex-col items-center gap-4">
          {/* Mode toggle */}
          <button
            onClick={() => setIsDark((p) => !p)}
            className="flex items-center gap-2 px-4 py-2 rounded-full transition-all"
            style={{
              backgroundColor: isDark
                ? "rgba(255,255,255,0.1)"
                : "rgba(0,0,0,0.07)",
              backdropFilter: "blur(12px)",
              border: `1px solid ${isDark ? "rgba(255,255,255,0.14)" : "rgba(0,0,0,0.08)"}`,
              color: isDark ? "#fff" : "#0A0A20",
              fontSize: 13,
              fontWeight: 500,
              gap: 8,
            }}
          >
            {isDark ? <Sun size={14} /> : <Moon size={14} />}
            {isDark
              ? "Switch to Light Mode"
              : "Switch to Dark Mode"}
          </button>

          {/* iPhone */}
          <IPhoneFrame>
            <div
              className="flex flex-col h-full"
              style={{
                backgroundColor: colors.bg,
                overflow: "hidden",
              }}
            >
              <div
                className="flex-1 overflow-y-auto"
                style={{ scrollbarWidth: "none" }}
              >
                {activeTab === "sleep"    && <SleepTab />}
                {activeTab === "trends"   && <TrendsTab />}
                {activeTab === "protocol" && <ProtocolTab />}
                {activeTab === "biology"  && <BiologyTab />}
                {activeTab === "activity" && <ActivityTab />}
              </div>
              <TabBar />
            </div>
          </IPhoneFrame>

          <p
            style={{
              color: isDark
                ? "rgba(255,255,255,0.25)"
                : "rgba(0,0,0,0.25)",
              fontSize: 11,
            }}
          >
            Better Sleep · Web Prototype
          </p>
        </div>
      </div>
    </ThemeContext.Provider>
  );
}