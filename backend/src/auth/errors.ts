export class AuthConfigurationError extends Error {
  constructor(message = "Authentication is not configured") {
    super(message);
    this.name = "AuthConfigurationError";
  }
}

export class InvalidCredentialsError extends Error {
  constructor() {
    super("Invalid email or password.");
    this.name = "InvalidCredentialsError";
  }
}

export class EmailTakenError extends Error {
  constructor() {
    super("An account with that email already exists.");
    this.name = "EmailTakenError";
  }
}

export class InvalidRefreshTokenError extends Error {
  constructor() {
    super("Refresh token is invalid or expired.");
    this.name = "InvalidRefreshTokenError";
  }
}

export class RefreshTokenReuseError extends Error {
  constructor() {
    super("Refresh token reuse detected.");
    this.name = "RefreshTokenReuseError";
  }
}

export class AccessTokenExpiredError extends Error {
  constructor() {
    super("Access token expired.");
    this.name = "AccessTokenExpiredError";
  }
}

export class InvalidAccessTokenError extends Error {
  constructor() {
    super("Access token is invalid.");
    this.name = "InvalidAccessTokenError";
  }
}
