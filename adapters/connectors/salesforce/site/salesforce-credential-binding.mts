// The configured org is non-secret. A CLI-backed resolver also exposes its
// pinned org so an unrelated connection cannot borrow its token.
type CredentialOrg = Readonly<{
  orgId?: unknown;
  resolveSecret?: (((...args: never[]) => unknown) & Readonly<{connectionOrgId?: unknown}>) | null;
}>;

export function matchesSalesforceCredentialOrg(credential: CredentialOrg | null | undefined, orgId: unknown) {
  return typeof orgId === 'string' && orgId.length > 0 &&
    credential?.orgId === orgId &&
    (credential.resolveSecret?.connectionOrgId === undefined ||
      credential.resolveSecret.connectionOrgId === orgId);
}
