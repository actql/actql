import {getCheckParameterAdmission, type CheckParameterAdmission} from '@actql/sdk';
const observed: CheckParameterAdmission | undefined = getCheckParameterAdmission({}, 'x');
if (observed) {
  const kind: 'parameter_declaration' = observed.kind;
  const supplier: 'caller' = observed.supplier;
  const schemaCid: string = observed.contract_schema_cid;
  for (const rule of observed.constraints) {
    if (rule.kind === 'numeric') {
      const minimum: number | undefined = rule.minimum;
      const integer: boolean = rule.integer;
      void minimum; void integer;
    }
    if (rule.kind === 'array_length') {
      const length: number = rule.length;
      void length;
    }
  }
  // @ts-expect-error Conditions confer no execution or approval permission.
  observed.next;
  // @ts-expect-error Checked conditions cannot be changed by a consumer.
  observed.supplier = 'operator';
  void kind; void supplier; void schemaCid;
}
