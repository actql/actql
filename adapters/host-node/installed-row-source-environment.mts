import {createHash} from 'node:crypto';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {rejectInstalledRowSource as fail} from './installed-row-source-mapping.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import type {sourceEnvironmentConstructionGeometry} from './installed-source-construction-geometry.mjs';

type Declared = Parameters<typeof sourceEnvironmentConstructionGeometry>[1];
type Value = Extract<SynchronousRuntimeData, object>;
type BaseEnvironment = Record<string, unknown> & {
  evidence_bundle_cid: unknown;
  connector_catalogs: unknown[];
  schema_snapshots: unknown[];
  connector_capabilities: unknown[];
  mapping_contracts?: unknown[];
  command_contracts?: unknown[];
};
type Body = Readonly<Record<string, unknown>>;
type Document = Body & Readonly<{evidence_bundle_cid: string}>;
type Result = Readonly<{wire: string; evidenceCid: string}>;
type RetainOriginal = (value: Result, document: Document, body: Body) => void;
type Construction = Readonly<{
  freeze<Data>(value: Data): Data;
  parse<Data extends Value>(project: () => Data): Data;
  sort<Data extends Value>(values: readonly unknown[], project: () => Data): Data;
  seal<Data extends Value>(body: Data): Data;
  hash(body: unknown, project: () => string): string;
  encode<Data extends Value>(document: unknown, project: () => Data): Data;
}>;

// A keyed request includes data values (not configuration identifiers).
// Keep exact version/target text; NFC must not broaden read approval identity.
export const valueCid = (value: unknown) => `sha256:${createHash('sha256')
  .update(canonicalValueJson(value, {dataKeys: true})).digest('hex')}`;

const byCid = (values: readonly string[]) => values.map(value => JSON.parse(value) as unknown)
  .sort((a, b) => {
    const left = valueCid(a);
    const right = valueCid(b);
    return left < right ? -1 : left > right ? 1 : 0;
  });

// The Check Environment of a restored row declaration: the Host's base
// environment with the declaration's Catalog, source views, contracts,
// manifest entry and evidence members, plus the create Mappings the common
// runtime generated from the connector's declared writes. Built only from
// regenerated declarations; nothing is read from the provider. Complete
// declared Command bodies keep their original Catalog/role correspondence for
// Common admission; this assembly does not confer permission or issue targets.
// Without Mappings or Commands the read-only environment remains unchanged.
// Checked contracts contain exact data text, including enum values and field
// names. Preserve those originals rather than applying configuration NFC.
export function rowSourceCheckEnvironment(baseWire: string, declared: Declared,
  mappings: readonly string[] = [], retainOriginal?: RetainOriginal, construction?: Construction) {
  const parse = <Value,>(wire: string): Value => construction === undefined ? JSON.parse(wire)
    : construction.freeze(JSON.parse(wire));
  const members = (values: readonly string[]) => construction === undefined ? byCid(values) : values.map(parse);
  const build = () => {
    const base = parse<BaseEnvironment>(baseWire);
    const {evidence_bundle_cid: _, ...body} = base;
    const commands = Object.hasOwn(declared, 'command_bodies')
      ? declared.command_bodies! : [];
    if (body.version !== 'actql-check-environment/0.1' ||
        body.connector_catalogs.length !== 0 ||
        body.schema_snapshots.length !== 0 ||
        body.connector_capabilities.length !== 0 ||
        body.connector_manifest !== undefined ||
        declared.evidence_schemas.length !== declared.view_bodies.length ||
        declared.evidence_capabilities.length !== declared.view_bodies.length ||
        !Array.isArray(mappings) || !Array.isArray(commands) ||
        (mappings.length !== 0 && body.mapping_contracts?.length !== 0) ||
        (commands.length !== 0 && body.command_contracts?.length !== 0)) {
      fail('InvalidRowSourceCheckEnvironmentBase');
    }
    const environment = {...body,
      schema_snapshots: members(declared.evidence_schemas),
      connector_capabilities: members(declared.evidence_capabilities),
      source_views: members(declared.view_bodies),
      contract_registry: members(declared.contracts),
      connector_catalogs: [parse(declared.catalog)],
      connector_manifest: {version: 'actql-connectors/0.1',
        connectors: [parse(declared.manifest_entry)]},
      ...(mappings.length === 0 ? {} : {mapping_contracts: members(mappings)}),
      ...(commands.length === 0 ? {} : {command_contracts: members(commands)})};
    return environment;
  };
  const environment = construction === undefined ? build() : construction.parse(build);
  if (construction !== undefined) {
    for (const section of ['schema_snapshots', 'connector_capabilities', 'source_views',
      'contract_registry', 'mapping_contracts', 'command_contracts'] as const) {
      const values = environment[section];
      if (!Object.isFrozen(values)) construction.sort(values!, () => {
        values!.sort((a, b) => {
          const left = valueCid(a), right = valueCid(b);
          return left < right ? -1 : left > right ? 1 : 0;
        });
        Object.freeze(values);return Object.freeze({});
      });
    }
    construction.seal(environment);
  }
  const evidenceCid = construction === undefined ? valueCid(environment)
    : construction.hash(environment, () => valueCid(environment));
  const document = Object.freeze({...environment, evidence_bundle_cid: evidenceCid});
  const encode = () => {
    const result = Object.freeze({
      wire: canonicalValueJson(document,
        {dataKeys: true}),
      evidenceCid});
    retainOriginal?.(result, document, environment);
    return result;
  };
  return construction === undefined ? encode() : construction.encode(document, encode);
}
