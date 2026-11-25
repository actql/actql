import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';
import {eventSchemas} from './event-schema.mjs';

const ownerPath = 'spec/contracts/actql-aoa.json';
const registryPath = 'spec/dependencies/aoa-pipeline-registry.json';
export const operations = ['TEA.calendar.bucket', 'TEA.calendar.series'] as const;
type Operation = (typeof operations)[number];
type EventSchemas = ReturnType<typeof eventSchemas>;
type SeriesProperties = EventSchemas['calendar_series']['properties'];
type CalendarParams = Omit<EventSchemas['calendar_bucket'], 'properties'> & {
  $schema?: string;
  $id?: string;
  properties: Pick<SeriesProperties, 'unit' | 'timezone' | 'week_start'> & {
    profile?: {type: string; additionalProperties: boolean; required: string[];
      properties: {conversion_law: {const: string}; table_bytes_cid: {type: string; pattern: string};
        tzdb_version: {type: string; minLength: number}}};
    start?: SeriesProperties['start'] | SeriesProperties['start']['oneOf'][0];
    end?: SeriesProperties['end'] | SeriesProperties['end']['oneOf'][0];
  };
};
type Owner = {execution_contracts: Record<string, unknown>;
  target_registry_requirements: Record<string, unknown>; pipeline_registry_file: string; pipeline_registry_cid: string};

const signature = (operation: Operation) => ({
  inputs: operation === operations[0] ? ['relation'] : [], output: 'relation',
});

// Compiled parameters bind endpoint Parameters through their existing owner
// and identify the selected original profile. They never carry table rows or
// authority, and do not replace the authored Calendar option schemas.
export function executionContract(operation: Operation) {
  assert(operations.includes(operation));
  const series = operation === operations[1];
  const source = eventSchemas()[series ? 'calendar_series' : 'calendar_bucket'];
  const params: CalendarParams = structuredClone(source);
  params.$schema = 'https://json-schema.org/draft/2020-12/schema';
  params.$id = `urn:actql:calendar-${series ? 'series' : 'bucket'}-params:0.1`;
  params.required.push('profile');
  params.properties.profile = {
    type: 'object', additionalProperties: false,
    required: ['conversion_law', 'table_bytes_cid', 'tzdb_version'],
    properties: {
      conversion_law: {const: 'actql-calendar-boundaries/0.1'},
      table_bytes_cid: {type: 'string', pattern: '^sha256:[a-f0-9]{64}$'},
      tzdb_version: {type: 'string', minLength: 1},
    },
  };
  if (series) {
    params.properties.start = structuredClone((source as EventSchemas['calendar_series']).properties.start.oneOf[0]);
    params.properties.end = structuredClone((source as EventSchemas['calendar_series']).properties.end.oneOf[0]);
  }
  return {
    operation, ...signature(operation), params_schema: params,
    semantics: {
      profile: 'exact_selected_CalendarProfile_original_table_bytes_CID_tzdb_version_and_conversion_law_for_same_checked_occurrence_and_timezone',
      endpoints: 'bind_original_non_null_timestamp_Parameters_then_validate_canonical_years_0001_to_9999_and_start_not_after_end',
      boundaries: 'original_selected_timezone_table_earliest_exact_fold_earliest_forward_gap_greatest_distinct_UTC_start_not_after_timestamp_and_least_distinct_UTC_end_after_timestamp',
      output: series ? 'complete_unclipped_intersecting_intervals_in_UTC_order_equal_range_empty_coincident_boundaries_collapse' : 'retain_original_input_fields_and_append_non_null_start_end_interval_for_original_time_field',
      authority: 'registration_and_lowering_are_not_executable_Plan_authorization_or_Runtime_support',
      runtime: 'existing_selected_TEA_input_output_control_work_retention_capacity_cancellation_and_cleanup_owners_no_ambient_timezone_or_fixed_milliseconds_substitution',
      unsupported: 'reject_before_execution_when_original_profile_or_required_runtime_obligation_cannot_be_enforced',
    },
  };
}

export function checkRegistration(aoa: Owner, registry: Record<string, unknown>) {
  for (const operation of operations) {
    const body = executionContract(operation);
    const ref = {pointer: `/execution_contracts/${operation}`, cid: machineCid(body)};
    assert.deepEqual(aoa.execution_contracts[operation], body);
    assert.deepEqual(aoa.target_registry_requirements[operation], {
      ...signature(operation), execution_contract: ref,
    });
    assert.deepEqual(registry[operation], {
      ...signature(operation), execution_contract: {file: ownerPath, ...ref},
    });
  }
  assert.equal(aoa.pipeline_registry_file, registryPath);
  assert.equal(aoa.pipeline_registry_cid, machineCid(registry));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const read = <Value,>(path: string): Value => JSON.parse(readFileSync(path, 'utf8'));
  const aoa = read<Owner>(ownerPath), registry = read<Record<string, unknown>>(registryPath);
  if (process.argv.includes('--write')) {
    for (const operation of operations) {
      const body = executionContract(operation);
      const ref = {pointer: `/execution_contracts/${operation}`, cid: machineCid(body)};
      aoa.execution_contracts[operation] = body;
      aoa.target_registry_requirements[operation] = {...signature(operation), execution_contract: ref};
      registry[operation] = {...signature(operation), execution_contract: {file: ownerPath, ...ref}};
    }
    aoa.pipeline_registry_cid = machineCid(registry);
    writeFileSync(registryPath, JSON.stringify(registry, null, 2) + '\n');
    writeFileSync(ownerPath, JSON.stringify(aoa, null, 2) + '\n');
  }
  checkRegistration(aoa, registry);
  console.log('Calendar compiled parameter registration verified; Runtime and public execution unverified.');
}
