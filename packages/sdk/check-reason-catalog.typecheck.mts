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
