// Explicit product declarations for the documented mock installation. These
// are input DATA to the existing Common Relation declaration owner, not a
// schema inferred from fixture rows, a Task, or a selected file's name.
// The trusted Host must select this catalogue and bind its original Project,
// profile, connection, runtime and installation generation independently.
export const mockChurnRiskCatalogue = Object.freeze([
  Object.freeze({
    connection: 'salesforce',
    connectorId: 'salesforce',
    registration: 'mock.salesforce',
    revision: 'mock',
    queryAliases: Object.freeze([
      Object.freeze({name: 'salesforce.accounts', resource: 'Account'}),
    ]),
    views: Object.freeze([
      Object.freeze({
        resource: 'Account',
        resource_kind: 'record',
        schema_wire: '{"Churn_Risk__c":{"nullable":false,"type":"string"},"Risk_Reason__c":{"nullable":true,"type":"string"},"description":{"nullable":false,"type":"string"},"id":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"}}',
        schema_cid: 'sha256:2bb86ad0dae4e6ab1cde7bb339f74cd3959dc572f6ad54f6da5487765709307d',
        facts_wire: '{"relation_keys":{"candidate_keys":[["id"]]}}',
      }),
    ]),
  }),
  Object.freeze({
    connection: 'snowflake',
    connectorId: 'snowflake',
    registration: 'mock.snowflake',
    revision: 'mock',
    queryAliases: Object.freeze([
      Object.freeze({name: 'snowflake.usage_30d', resource: 'usage_30d'}),
    ]),
    views: Object.freeze([
      Object.freeze({
        resource: 'usage_30d',
        resource_kind: 'table',
        schema_wire: '{"account_id":{"nullable":false,"type":"string"},"active_users":{"nullable":false,"type":"int64"},"trend":{"nullable":false,"type":"string"}}',
        schema_cid: 'sha256:fd038c1aa8fe013d4838819a6011e18aee81a04a179f1994a548ff292dfae424',
        facts_wire: '{"relation_keys":{"candidate_keys":[["account_id"]]}}',
      }),
    ]),
  }),
]);

// No request schema or acquisition override is supplied: Common retains its
// existing empty original request, finite scan and projection-only contract.
// The live file's declared key must be checked, not replaced with these facts.
// This asset grants no read/write/model permission, capacity or cold custody.
