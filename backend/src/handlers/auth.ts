import type { Request, Response } from "express";
import {
  createRequestId,
  DatabaseOperationError,
  DatabaseUnavailableError,
  logDatabaseFailure,
  logInternalFailure,
} from "../errors.js";
import {
  AuthConfigurationError,
  ClerkAccountDeletionError,
  LocalUserNotFoundError,
} from "../auth/errors.js";
import { deleteClerkUser } from "../auth/client.js";
import type { AuthenticatedUser } from "../auth/middleware.js";
import { deleteUser, findById, toPublicUser } from "../db/repositories/users.js";

function sendError(res: Response, requestId: string, error: unknown, endpoint: string): void {
  if (error instanceof LocalUserNotFoundError) {
    res.status(401).json({ error: "Authentication is required.", code: "UNAUTHORIZED", requestId });
    return;
  }
  if (error instanceof AuthConfigurationError || error instanceof ClerkAccountDeletionError) {
    logInternalFailure(requestId, { endpoint }, error);
    res.status(503).json({
      error: "Account services are temporarily unavailable. Please try again shortly.",
      code: "SERVICE_UNAVAILABLE",
      requestId,
    });
    return;
  }
  if (error instanceof DatabaseUnavailableError || error instanceof DatabaseOperationError) {
    logDatabaseFailure(requestId, { endpoint }, error);
    res.status(503).json({
      error: "Account services are temporarily unavailable. Please try again shortly.",
      code: "SERVICE_UNAVAILABLE",
      requestId,
    });
    return;
  }
  logInternalFailure(requestId, { endpoint }, error);
  res.status(500).json({ error: "An unexpected error occurred.", code: "INTERNAL_ERROR", requestId });
}

export async function handleMe(req: Request, res: Response): Promise<void> {
  const requestId = createRequestId();
  try {
    const user = await findById((req.user as AuthenticatedUser).id);
    if (!user) throw new LocalUserNotFoundError();
    res.status(200).json({ user: toPublicUser(user) });
  } catch (error) {
    sendError(res, requestId, error, "auth-me");
  }
}

export async function handleDeleteAccount(req: Request, res: Response): Promise<void> {
  const requestId = createRequestId();
  try {
    const user = req.user as AuthenticatedUser;
    if (!user.clerkUserId) throw new AuthConfigurationError("The Clerk user id is missing.");
    // Personal data goes first. If the database fails, nothing was removed and
    // the still-valid Clerk session can retry. If Clerk fails afterwards, the
    // data is already gone and a retry with the same session finishes the
    // identity removal (the middleware re-creates an empty local row, which
    // the retry deletes again). The old order could strand personal data
    // behind an identity that no longer existed to request its deletion.
    await deleteUser(user.id);
    await deleteClerkUser(user.clerkUserId);
    res.status(204).end();
  } catch (error) {
    sendError(res, requestId, error, "account-delete");
  }
}
