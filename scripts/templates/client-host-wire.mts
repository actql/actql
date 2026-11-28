/* @wire-bindings */

const valid = structuralWireValidator({schemas});

export const clientHostOperations: readonly ClientHostOperation[] =
  Object.freeze(Object.keys(operationKeys) as ClientHostOperation[]);

export function clientHostRequestKeys(operation: unknown, body: unknown = {}): string[] | undefined {
  const key = operation as string;
  if (!Object.hasOwn(operationKeys, key)) return undefined;
  return [...operationKeys[key], ...Object.keys(optionalRequestFields[key] ?? {}).filter(field =>
    body !== null && typeof body === 'object' && Object.hasOwn(body, field))];
}

export function validClientRequestOptionalFields(operation: unknown, body: unknown): boolean {
  return Object.entries(optionalRequestFields[operation as string] ?? {}).every(([key, schema]) =>
    !Object.hasOwn(body as object, key) || valid((body as Readonly<Record<string, unknown>>)[key], schema));
}

/* @wire-predicates */

export function validRunStateShape(value: unknown): value is WireRunStateShape {
  return valid(value, schemas.run_state);
}

export function validCheckOutcomeShape(value: unknown): value is WireCheckOutcomeShape {
  return valid(value, schemas.check_outcome) && wireObject(value) &&
    value.outcome_schema_cid === checkOutcomeSchemaCid;
}

function matchesConnection(
  value: unknown, selected: WireConnectionShape,
  rule: Readonly<{matchConnection: readonly string[]; requireRequested: Readonly<Record<string, string>>}>,
): boolean {
  // Both operands have already passed the selected registered object shape.
  const response = value as Readonly<Record<string, unknown>>;
  const connection = selected as Readonly<Record<string, unknown>>;
  return rule.matchConnection.every(field => response[field] === connection[field]) &&
    Object.entries(rule.requireRequested).every(([field, required]) =>
      connection[field] !== required || response[field] === required);
}

export function validProfileContract(value: unknown, selected: WireConnectionShape): value is WireProfileShape {
  return validConnectionShape(selected) && validProfileShape(value) &&
    matchesConnection(value, selected, responseRules.profile);
}

export function validAdmissionContract(value: unknown, selected: WireConnectionShape): value is WireAdmissionShape {
  return validConnectionShape(selected) && validAdmissionShape(value) &&
    matchesConnection(value, selected, responseRules.admission);
}

export function validRunWaitContract(value: unknown, since: number | null): value is WireRunStateShape {
  const rule = requestRules.run_wait;
  return valid(value, schemas[rule.schema]) && wireObject(value) &&
    (since === null || valid(since, schemas[rule.schema].properties![rule.revisionField])) &&
    (rule.stableStatuses as readonly unknown[]).includes(value.status) &&
    (since === null || (value[rule.revisionField] as number) > since);
}

function matchesRequest(value: unknown, expected: string, rule: typeof requestRules.held): boolean {
  const field = rule.matchRequest;
  return valid(expected, schemas[rule.expectedSchema].properties![field]) &&
    rule.schemas.some(name => valid(value, schemas[name]) &&
      (!Object.hasOwn(schemas[name].properties!, field) || (wireObject(value) && value[field] === expected)));
}

export function validHeldContract(value: unknown, expected: string): value is WireHeldShape {
  return matchesRequest(value, expected, requestRules.held);
}

export function validRequestLookupContract(value: unknown, expected: string):
  value is WireLookupFoundShape | WireLookupNotFoundShape | WireLookupUnknownShape | WireHeldShape {
  return matchesRequest(value, expected, requestRules.request_lookup);
}

export function validCheckOutcomeContract(value: unknown): value is WireCheckOutcomeShape {
  if (!validCheckOutcomeShape(value)) return false;
  type Report = Extract<WireCheckOutcomeShape, {outcome: 'completed'}>['report'];
  type PartialReport = Extract<WireCheckOutcomeShape, {outcome: 'failed'}>['partial_report'];
  const {report: complete, partial_report: partial} = value as
    Readonly<{report?: Report; partial_report?: PartialReport}>;
  const report = complete ?? partial;
  if (!report) return true;
  const documents = new Map(report.inputs.map(input => [input.document_id, input]));
  const occurrences: readonly Readonly<{
    code: string; location?: WireCheckLocationShape; fixes?: readonly WireCheckFixShape[];
  }>[] = [...report.reasons, ...report.requirements, ...report.coverage.limits];
  for (const rule of reportRules) {
    switch (rule) {
      case 'unique_document_ids':
        if (documents.size !== report.inputs.length) return false;
        break;
      case 'input_document_kinds': {
        const program = documents.get('program');
        if (program ? program.kind !== 'structured' || documents.has('source') ||
            documents.has('parameter_declarations') : documents.get('source')?.kind !== 'text') return false;
        if (report.inputs.some(input => input.document_id !== 'source' && input.kind !== 'structured')) return false;
        break;
      }
      case 'locations_match_input':
        for (const reason of occurrences) {
          const location = reason.location;
          if (!location) continue;
          const input = documents.get(location.document_id);
          if (!input || input.revision !== location.revision || input.kind !== location.kind) return false;
          if (location.kind === 'text' && (location.start_byte > location.end_byte ||
              location.end_byte > input.byte_length)) return false;
        }
        break;
      case 'fix_targets_match_exact_eof':
        for (const reason of occurrences) {
          for (const fix of reason.fixes ?? []) {
            const input = documents.get(fix.target.document_id);
            if (!input || input.kind !== 'text' || input.revision !== fix.target.revision) return false;
            if (fix.edits.some(edit => edit.start_byte !== input.byte_length || edit.end_byte !== input.byte_length)) return false;
          }
        }
        break;
      default: {
        const exhaustive: never = rule;
        throw new Error(`UnsupportedCheckReportRule:${exhaustive}`);
      }
    }
  }
  return true;
}
