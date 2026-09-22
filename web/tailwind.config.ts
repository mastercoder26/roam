import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        accent: "#3158D4",
        "accent-foreground": "#ffffff",
        safety: "#C76A20",
        danger: "#BD4542",
        positive: "#277A54",
        canvas: "#F4F5F2",
        card: "#FFFFFF",
        "card-elevated": "#ECEFEB",
        "ink-primary": "#191C20",
        difficulty: {
          "very-easy": "#198A62",
          easy: "#55A766",
          moderate: "#D49A16",
          hard: "#E77B12",
          "very-hard": "#D44C42",
        },
      },
      textColor: {
        "ink-secondary": "#5F656B",
        "ink-tertiary": "#8A9095",
        "ink-label": "#6E7479",
      },
      borderColor: {
        card: "#DFE2DD",
        "card-strong": "#C9CEC7",
      },
      backgroundColor: {
        disabled: "#E5E1D7",
      },
      borderRadius: {
        roam: "12px",
        "roam-sm": "9px",
        "roam-lg": "16px",
        "roam-hero": "18px",
        "roam-tiny": "8px",
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
        roam: "0 1px 2px rgba(25,28,32,0.04)",
        "roam-md": "0 8px 24px rgba(25,28,32,0.07)",
        "roam-lg": "0 16px 44px rgba(25,28,32,0.1)",
        "roam-hero": "0 24px 64px rgba(25,28,32,0.12)",
      },
    },
  },
  plugins: [],
};

export default config;
