// The configured org is non-secret. A CLI-backed resolver also exposes its
// pinned org so an unrelated connection cannot borrow its token.
export function matchesSalesforceCredentialOrg(credential, orgId) {
  return typeof orgId === 'string' && orgId.length > 0 &&
    credential?.orgId === orgId &&
    (credential.resolveSecret?.connectionOrgId === undefined ||
      credential.resolveSecret.connectionOrgId === orgId);
}
