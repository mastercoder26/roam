import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        accent: "#2557F5",
        "accent-foreground": "#ffffff",
        safety: "#E77B12",
        danger: "#C83E3A",
        positive: "#198A62",
        canvas: "#F7F4EC",
        card: "#FFFEFA",
        "card-elevated": "#EFECDF",
        "ink-primary": "#18233C",
        difficulty: {
          "very-easy": "rgb(77, 209, 115)",
          easy: "rgb(122, 219, 107)",
          moderate: "rgb(247, 199, 56)",
          hard: "rgb(255, 153, 64)",
          "very-hard": "rgb(255, 107, 82)",
        },
      },
      textColor: {
        "ink-secondary": "#626A78",
        "ink-tertiary": "#9297A0",
        "ink-label": "#717887",
      },
      borderColor: {
        card: "#DED9CC",
        "card-strong": "#C8C1B1",
      },
      backgroundColor: {
        disabled: "#E5E1D7",
      },
      borderRadius: {
        roam: "16px",
        "roam-sm": "11px",
        "roam-lg": "20px",
        "roam-hero": "22px",
        "roam-tiny": "10px",
      },
      spacing: {
        18: "4.5rem",
      },
      fontFamily: {
        sans: [
          "-apple-system",
          "BlinkMacSystemFont",
          "SF Pro Text",
          "SF Pro Display",
          "Inter",
          "system-ui",
          "sans-serif",
        ],
      },
      fontSize: {
        display: ["clamp(2.7rem, 7vw, 5.9rem)", { lineHeight: "0.91", letterSpacing: "-0.065em" }],
      },
      boxShadow: {
        roam: "0 1px 2px rgba(24,35,60,0.06)",
        "roam-md": "0 12px 30px rgba(24,35,60,0.09)",
        "roam-lg": "0 18px 45px rgba(24,35,60,0.14)",
        "roam-hero": "0 30px 80px rgba(24,35,60,0.16)",
      },
    },
  },
  plugins: [],
};

export default config;
