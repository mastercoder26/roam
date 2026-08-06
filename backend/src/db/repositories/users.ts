import { getPool } from "../pool.js";
import type { PublicUser, UserRecord } from "../types.js";
import { isUniqueViolation, queryDatabase } from "./helpers.js";

interface UserRow extends Record<string, unknown> {
  id: string;
  email: string;
  password_hash: string | null;
  display_name: string | null;
  created_at: Date;
  updated_at: Date;
  email_verified_at: Date | null;
  deleted_at: Date | null;
}

function mapUser(row: UserRow): UserRecord {
  return {
    id: row.id,
    email: row.email,
    passwordHash: row.password_hash,
    displayName: row.display_name,
    createdAt: new Date(row.created_at),
    updatedAt: new Date(row.updated_at),
    emailVerifiedAt: row.email_verified_at ? new Date(row.email_verified_at) : null,
    deletedAt: row.deleted_at ? new Date(row.deleted_at) : null,
  };
}

export function toPublicUser(user: UserRecord): PublicUser {
  return { id: user.id, email: user.email, displayName: user.displayName };
}

export async function findUserByEmail(email: string): Promise<UserRecord | null> {
  const result = await queryDatabase<UserRow>(getPool(), `
    SELECT id, email, password_hash, display_name, created_at, updated_at,
           email_verified_at, deleted_at
    FROM users WHERE email = $1 AND deleted_at IS NULL LIMIT 1
  `, [email]);
  const row = result.rows[0];
  return row ? mapUser(row) : null;
}

export async function findUserById(id: string): Promise<UserRecord | null> {
  const result = await queryDatabase<UserRow>(getPool(), `
    SELECT id, email, password_hash, display_name, created_at, updated_at,
           email_verified_at, deleted_at
    FROM users WHERE id = $1 AND deleted_at IS NULL LIMIT 1
  `, [id]);
  const row = result.rows[0];
  return row ? mapUser(row) : null;
}

export async function createUser(input: {
  email: string;
  passwordHash: string;
  displayName: string | null;
}): Promise<UserRecord> {
  const result = await queryDatabase<UserRow>(getPool(), `
    WITH new_user AS (
      INSERT INTO users (email, password_hash, display_name)
      VALUES ($1, $2, $3)
      RETURNING id, email, password_hash, display_name, created_at, updated_at,
                email_verified_at, deleted_at
    ), new_identity AS (
      INSERT INTO auth_identities (user_id, provider, provider_subject)
      SELECT id, 'password', email::text FROM new_user
    )
    SELECT * FROM new_user
  `, [input.email, input.passwordHash, input.displayName]);
  const row = result.rows[0];
  if (!row) throw new Error("User insert returned no row");
  return mapUser(row);
}

export async function softDeleteUser(id: string): Promise<void> {
  await queryDatabase(getPool(), `
    UPDATE users SET deleted_at = now(), updated_at = now()
    WHERE id = $1 AND deleted_at IS NULL
  `, [id]);
}

export { isUniqueViolation };
export type { UserRecord };
export const findByEmail = findUserByEmail;
export const findById = findUserById;
export const create = createUser;
export const softDelete = softDeleteUser;
