# Proposed Salesforce Connector test-org setup

Status: proposal only. No org alias, instance URL, credentials, schema-change
approval, or write authorization has been supplied. Do not run these steps
against an existing unrelated service connection or any production org.

## Isolated resources

Use an ActQL-only sandbox or Developer org. Record its alias, org ID, user,
instance URL, and API version outside this repository. For local use, the
optional Salesforce CLI adapter can resolve that fixed binding from an
existing `sf org login web` session. An explicitly configured Site secret
manager remains an alternative; Cloud credentials are a separate connection
choice. The Site secret resolver supplies the token to scoped operations.
Never put the token into fixtures, logs, or a general Connector environment
map, and never fall back from failed local authentication to Cloud.

Keep `Account` as a read-only comparison resource. Provision a dedicated
custom object after review. `ActQL_Test_Record__c` is a proposed name, not an
assumed existing object. Its proposed fields are:

| Field | Type | Constraint and test purpose |
| --- | --- | --- |
| `External_Key__c` | Text | Required, unique External ID; exact upsert target and duplicate rejection. |
| `Optional_Text__c` | Text | Nullable; distinguish omitted field from explicit JSON `null`. |
| `Amount__c` | Number/Decimal | Precision and scale fixed during setup; typed acquisition and update. |
| `Observed_At__c` | DateTime | UTC input/output and ordering semantics. |
| `Read_Only__c` | Formula or otherwise non-writable field | Verify describe-level create/update denial. |

The Connector must use names and constraints observed from the authorized
Resource Catalog Snapshot. None of these names is hard-coded into its product
logic. If the chosen org cannot provide an equivalent read-only field, record
the fixture difference rather than declaring that case covered.

## Minimum access to request

- API access and object/field metadata visibility for `Account` and the
  dedicated object; read access to the exact fields required by each test.
- Query/read access to `Account`, with no Account create/update/delete grant.
- Create and update access only to the dedicated object and its intended
  writable fields; no delete grant for the initial profile.
- Access to the unique External ID field needed for upsert and target checks.
- A scoped Site credential grant for the exact origin, operation, Site,
  generation, dispatch attempt, expiry, and use count. Distinct read and write
  grants are required; a metadata/discovery grant does not authorize writes.

Do not grant administrative setup, broad object mutation, or unrestricted
network egress to the runtime identity. Schema provisioning itself is a
separate, explicitly approved administrative step.

## Review and evidence checklist

Before any live write, obtain the exact object/field names, describe responses,
org alias, API version, connection authority, chosen credential source, and
explicit create/update/upsert authorization. Confirm that the test user can
observe the required metadata and that an unprivileged user cannot. Capture
the exact Resource Catalog observation and current authority separately.

Exercise pagination, field omission versus NULL, duplicate External ID,
permission loss, schema drift, rate limits, partial Collections results,
cancel, and lost responses. Redact tokens and business data. Preserve unknown
write attempts for reconciliation and never automatically replay them. Mark
all live-provider cases unverified until this isolated setup is available.
