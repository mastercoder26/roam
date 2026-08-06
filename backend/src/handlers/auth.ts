import type { Request, Response } from "express";
import { z } from "zod";
import { createRequestId, DatabaseOperationError, DatabaseUnavailableError, logDatabaseFailure, logInternalFailure, RequestValidationError } from "../errors.js";
import { AuthConfigurationError, EmailTakenError, InvalidCredentialsError, InvalidRefreshTokenError, RefreshTokenReuseError } from "../auth/errors.js";
import { AuthServiceError, deleteAccount, getCurrentUser, login, logout, refreshSession, signup } from "../auth/service.js";
import type { AuthenticatedUser } from "../auth/middleware.js";

const emailSchema = z.string({ invalid_type_error: "email is required and must be a string" }).trim()
  .email("email must be valid").max(320, "email must be at most 320 characters")
  .transform((email) => email.toLowerCase());
const passwordSchema = z.string({ invalid_type_error: "password is required and must be a string" })
  .min(8, "password must be at least 8 characters").max(128, "password must be at most 128 characters");
const signupSchema = z.object({ email: emailSchema, password: passwordSchema, displayName: z.string().trim().min(1).max(80).optional() }).strict();
const loginSchema = z.object({ email: emailSchema, password: passwordSchema }).strict();
const refreshSchema = z.object({ refreshToken: z.string().min(1, "refreshToken is required") }).strict();

function validationMessage(error: z.ZodError): string {
  const issue = error.issues[0];
  return issue.code === z.ZodIssueCode.unrecognized_keys
    ? `Request body contains unrecognized field: ${issue.keys[0]}`
    : issue.message;
}

function parse<T>(schema: z.ZodType<T>, body: unknown): T {
  const result = schema.safeParse(body);
  if (result.success) return result.data;
  throw new RequestValidationError(validationMessage(result.error));
}

export function validateSignupRequest(body: unknown): z.infer<typeof signupSchema> {
  return parse(signupSchema, body);
}

export function validateLoginRequest(body: unknown): z.infer<typeof loginSchema> {
  return parse(loginSchema, body);
}

function userAgent(req: Request): string | null {
  const value = typeof req.get === "function" ? req.get("user-agent") : undefined;
  return value ? value.slice(0, 512) : null;
}

function sendError(res: Response, requestId: string, error: unknown, endpoint: string): void {
  if (error instanceof RequestValidationError) {
    res.status(400).json({ error: error.message, code: "VALIDATION_ERROR", requestId });
    return;
  }
  if (error instanceof EmailTakenError) {
    res.status(409).json({ error: error.message, code: "EMAIL_TAKEN", requestId });
    return;
  }
  if (error instanceof AuthServiceError) {
    res.status(error.status).json({ error: error.message, code: error.code, requestId });
    return;
  }
  if (error instanceof InvalidCredentialsError || error instanceof InvalidRefreshTokenError || error instanceof RefreshTokenReuseError) {
    res.status(401).json({ error: error.message, code: "UNAUTHORIZED", requestId });
    return;
  }
  if (error instanceof AuthConfigurationError || error instanceof DatabaseUnavailableError || error instanceof DatabaseOperationError) {
    logDatabaseFailure(requestId, { endpoint }, error);
    res.status(503).json({ error: "Account services are temporarily unavailable. Please try again shortly.", code: "SERVICE_UNAVAILABLE", requestId });
    return;
  }
  logInternalFailure(requestId, { endpoint }, error);
  res.status(500).json({ error: "An unexpected error occurred.", code: "INTERNAL_ERROR", requestId });
}

export async function handleSignup(req: Request, res: Response): Promise<void> {
  const requestId = createRequestId();
  try { res.status(201).json(await signup(validateSignupRequest(req.body), userAgent(req))); }
  catch (error) { sendError(res, requestId, error, "auth-signup"); }
}

export async function handleLogin(req: Request, res: Response): Promise<void> {
  const requestId = createRequestId();
  try { res.status(200).json(await login(validateLoginRequest(req.body), userAgent(req))); }
  catch (error) { sendError(res, requestId, error, "auth-login"); }
}

export async function handleRefresh(req: Request, res: Response): Promise<void> {
  const requestId = createRequestId();
  try { res.status(200).json(await refreshSession(parse(refreshSchema, req.body).refreshToken, userAgent(req))); }
  catch (error) { sendError(res, requestId, error, "auth-refresh"); }
}

export async function handleLogout(req: Request, res: Response): Promise<void> {
  const requestId = createRequestId();
  try { await logout(parse(refreshSchema, req.body).refreshToken); res.status(204).end(); }
  catch (error) { sendError(res, requestId, error, "auth-logout"); }
}

export async function handleMe(req: Request, res: Response): Promise<void> {
  const requestId = createRequestId();
  try { res.status(200).json({ user: await getCurrentUser((req.user as AuthenticatedUser).id) }); }
  catch (error) { sendError(res, requestId, error, "auth-me"); }
}

export async function handleDeleteAccount(req: Request, res: Response): Promise<void> {
  const requestId = createRequestId();
  try { await deleteAccount((req.user as AuthenticatedUser).id); res.status(204).end(); }
  catch (error) { sendError(res, requestId, error, "account-delete"); }
}
