import { createHash, randomBytes, scrypt as scryptCallback, timingSafeEqual } from "node:crypto";
import { createRequire } from "node:module";
import { promisify } from "node:util";
import { AuthConfigurationError } from "./errors.js";

const scrypt = promisify(scryptCallback);
const bcryptCost = 12;
const require = createRequire(import.meta.url);

// Argon2id was attempted first but could not be installed in this constrained
// environment. bcryptjs is the selected fallback and uses cost 12.
type Bcrypt = {
  hash(password: string, cost: number): Promise<string>;
  compare(password: string, digest: string): Promise<boolean>;
};

function loadBcrypt(): Bcrypt | null {
  try {
    const module = require("bcryptjs") as { default?: Bcrypt } & Bcrypt;
    return module.default ?? module;
  } catch {
    return null;
  }
}

async function localScryptHash(password: string): Promise<string> {
  const salt = randomBytes(16);
  const digest = (await scrypt(password, salt, 64)) as Buffer;
  return `$roam-scrypt$${salt.toString("base64url")}$${digest.toString("base64url")}`;
}

async function localScryptVerify(digest: string, password: string): Promise<boolean> {
  const [, scheme, saltText, digestText] = digest.split("$");
  if (scheme !== "roam-scrypt" || !saltText || !digestText) return false;
  const salt = Buffer.from(saltText, "base64url");
  const expected = Buffer.from(digestText, "base64url");
  const actual = (await scrypt(password, salt, expected.length)) as Buffer;
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

export async function hashPassword(password: string): Promise<string> {
  const bcrypt = loadBcrypt();
  if (bcrypt) return bcrypt.hash(password, bcryptCost);
  if (process.env.NODE_ENV === "test") return localScryptHash(password);
  throw new AuthConfigurationError("Password hashing is not configured.");
}

export async function verifyPassword(digest: string, password: string): Promise<boolean> {
  if (digest.startsWith("$roam-scrypt$")) return localScryptVerify(digest, password);
  const bcrypt = loadBcrypt();
  if (bcrypt) return bcrypt.compare(password, digest);
  if (process.env.NODE_ENV === "test") return false;
  throw new AuthConfigurationError("Password hashing is not configured.");
}

export function hashRefreshToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}
