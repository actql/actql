// Test-only boundary for the compiler's existing issued-query conformance exports.
export type Requirement = Readonly<{
  request: unknown;
  source_ref: string;
  source_contract_cid: string;
  output_contract_cid: string;
  owner: unknown;
  parameter_values_cid: string;
}>;
export type FixtureOptions = Readonly<{
  outputRows?: number;
  artifactBytes?: number;
  early?: boolean;
}>;
export type RuntimeCreate = (...args: [...string[], number, (attempt: unknown) => boolean]) => unknown;
