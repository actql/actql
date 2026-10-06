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
    const schemaCid: string = requirement.facts.schema_cid;
    // @ts-expect-error The context is not the caller's authored input location.
    requirement.location;
    // @ts-expect-error A Requirement grants no policy write/approval or Run permission.
    requirement.next;
    // @ts-expect-error The retained condition remains immutable.
    requirement.facts.supplier = 'caller';
    void supplier; void stage; void schemaCid;
  }
}
