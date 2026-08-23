import type { Config } from "tailwindcss";

// Ported 1:1 from ios/Roam/Models/Theme.swift (`dark` palette, the app's
// default theme) and ios/Roam/Utilities/DesignSystem.swift. Design choices are
// intentionally fixed to that single theme rather than made configurable.
const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        accent: "rgb(5, 107, 235)",
        "accent-foreground": "#ffffff",
        safety: "rgb(255, 148, 0)",
        danger: "rgb(209, 46, 43)",
        positive: "rgb(51, 199, 89)",
        canvas: "rgb(18, 18, 18)",
        card: "rgb(30, 30, 30)",
        "card-elevated": "rgb(36, 36, 36)",
        "ink-primary": "rgb(241, 241, 241)",
        difficulty: {
          "very-easy": "rgb(77, 209, 115)",
          easy: "rgb(122, 219, 107)",
          moderate: "rgb(247, 199, 56)",
          hard: "rgb(255, 153, 64)",
          "very-hard": "rgb(255, 107, 82)",
        },
      },
      textColor: {
        "ink-secondary": "rgba(255, 255, 255, 0.60)",
        "ink-tertiary": "rgba(255, 255, 255, 0.38)",
        "ink-label": "rgba(255, 255, 255, 0.64)",
      },
      borderColor: {
        card: "rgba(255, 255, 255, 0.10)",
        "card-strong": "rgba(255, 255, 255, 0.16)",
      },
      backgroundColor: {
        disabled: "rgba(255, 255, 255, 0.14)",
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
      boxShadow: {
        roam: "0 2px 5px rgba(0,0,0,0.35)",
        "roam-md": "0 4px 10px rgba(0,0,0,0.5)",
        "roam-lg": "0 7px 16px rgba(0,0,0,0.65)",
        "roam-hero": "0 8px 18px rgba(0,0,0,0.7)",
      },
    },
  },
  plugins: [],
};

export default config;
