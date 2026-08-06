declare module "bcryptjs" {
  export function hash(password: string, cost: number): Promise<string>;
  export function compare(password: string, digest: string): Promise<boolean>;
  const bcrypt: { hash: typeof hash; compare: typeof compare };
  export default bcrypt;
}
