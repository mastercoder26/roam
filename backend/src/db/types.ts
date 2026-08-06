export interface UserRecord {
  id: string;
  email: string;
  passwordHash: string | null;
  displayName: string | null;
  createdAt: Date;
  updatedAt: Date;
  emailVerifiedAt: Date | null;
  deletedAt?: Date | null;
}

export interface PublicUser {
  id: string;
  email: string;
  displayName: string | null;
}

export type DriverStage = "permit" | "provisional" | "licensed";

export interface ProfileRecord {
  userId: string;
  displayName: string | null;
  stage: DriverStage | null;
  payload: Record<string, unknown>;
  updatedAt: Date;
}
