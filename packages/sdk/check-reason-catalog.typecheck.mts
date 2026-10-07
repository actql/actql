import {getCheckReasonCatalogInfo, getCheckReasonCatalogEntry,
  type CheckReasonCatalogEntry, type KnownCheckReasonCode} from '@actql/sdk';
const version: 'actql-check-reason-catalog/0.1' = getCheckReasonCatalogInfo().version;
const code: KnownCheckReasonCode = 'parameter_value_required';
const entry: CheckReasonCatalogEntry | undefined = getCheckReasonCatalogEntry(code);
if (entry) {
  const severity: 'error' | 'warning' | 'info' = entry.default_severity;
  const revision: string = getCheckReasonCatalogInfo().revision;
  // @ts-expect-error Metadata does not authorize execution or establish a verdict.
  entry.verified;
  // @ts-expect-error Public catalog metadata is immutable.
  entry.default_severity = 'error';
  void severity; void revision;
}
void version;

const {getCheckContextRequirements} = await import('@actql/sdk');
const contexts = getCheckContextRequirements({});
if (contexts) {
  for (const requirement of contexts) {
    const supplier: 'checking_context_owner' = requirement.facts.supplier;
    const stage: 'checking' = requirement.facts.stage;
    if (requirement.code === 'numeric_reduction_profile_required') {
      const profileCid: string = requirement.facts.profile_cid;
      // @ts-expect-error A pinned profile condition is not a schema-pointer condition.
      requirement.facts.schema_pointer;
      void profileCid;
    } else {
      const schemaCid: string = requirement.facts.schema_cid;
      // @ts-expect-error Capacity admission does not select a numeric profile.
      requirement.facts.profile_cid;
      void schemaCid;
    }
    // @ts-expect-error The context is not the caller's authored input location.
    requirement.location;
    // @ts-expect-error A Requirement grants no policy write/approval or Run permission.
    requirement.next;
    // @ts-expect-error The retained condition remains immutable.
    requirement.facts.supplier = 'caller';
    void supplier; void stage;
  }
}
