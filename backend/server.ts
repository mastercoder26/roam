import { config } from "dotenv";
import { resolve } from "node:path";
import express from "express";
import { handleDifficulty } from "./src/handlers/difficulty.js";

// `server.ts` lives in `backend/`, alongside the local environment files.
config({ path: resolve(import.meta.dirname, ".env.local") });
config({ path: resolve(import.meta.dirname, ".env") });

function getAllowedOrigins(): string[] {
  const raw = process.env.ALLOWED_ORIGINS ?? "*";
  if (raw === "*") return ["*"];
  return raw.split(",").map((o) => o.trim()).filter(Boolean);
}

const app = express();
const port = Number(process.env.PORT ?? 3000);
const allowedOrigins = getAllowedOrigins();

app.use(express.json());

app.use((req, res, next) => {
  const origin = req.headers.origin ?? "";

  if (allowedOrigins.includes("*")) {
    res.setHeader("Access-Control-Allow-Origin", "*");
  } else if (origin && allowedOrigins.includes(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
  }

  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).end();
    return;
  }

  next();
});

app.post("/api/route/difficulty", (req, res) => {
  void handleDifficulty(req, res);
});

app.listen(port, () => {
  console.log(`Swerve API listening on http://localhost:${port}`);
});
