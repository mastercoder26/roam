import { createClerkClient } from "@clerk/backend";
import { AuthConfigurationError, ClerkAccountDeletionError } from "./errors.js";

function clerkSecretKey(): string {
  const secretKey = process.env.CLERK_SECRET_KEY?.trim();
  if (!secretKey) throw new AuthConfigurationError("CLERK_SECRET_KEY is not configured.");
  return secretKey;
}

function isNotFound(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    (error as { status?: unknown }).status === 404
  );
}

export async function deleteClerkUser(clerkUserId: string): Promise<void> {
  try {
    const clerk = createClerkClient({ secretKey: clerkSecretKey() });
    await clerk.users.deleteUser(clerkUserId);
  } catch (error) {
    if (error instanceof AuthConfigurationError) throw error;
    // Already gone (e.g. a retry after a response was lost): deletion is done.
    if (isNotFound(error)) return;
    throw new ClerkAccountDeletionError(error);
  }
}
