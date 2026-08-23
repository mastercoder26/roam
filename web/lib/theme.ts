import type { DifficultyLabel, RouteDemandLevel } from "./types";

// 1:1 with ThemeCatalog.darkDifficultyRamp in ios/Roam/Models/Theme.swift.
export function difficultyColor(label: DifficultyLabel): string {
  switch (label) {
    case "Very Easy":
      return "var(--difficulty-very-easy)";
    case "Easy":
      return "var(--difficulty-easy)";
    case "Moderate":
      return "var(--difficulty-moderate)";
    case "Hard":
      return "var(--difficulty-hard)";
    case "Very Hard":
      return "var(--difficulty-very-hard)";
  }
}

export function demandColor(level: RouteDemandLevel): string {
  switch (level) {
    case "low":
      return "var(--positive)";
    case "moderate":
    case "high":
      return "var(--safety)";
  }
}
