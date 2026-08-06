export interface AuthenticatedUser {
  id: string;
  email: string;
}

declare global {
  namespace Express {
    interface User extends AuthenticatedUser {}
  }
}

export {};
