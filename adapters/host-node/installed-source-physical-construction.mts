import {types as nodeTypes} from 'node:util';
import type {checkInstalledDuckDBSourceProfile} from './installed-duckdb-profile.mjs';

type Original = Readonly<{root: string; principalId: string}>;
type MaterialInventory = {
  inputs: unknown[];
  nodes: bigint;
  text: bigint;
  wire: bigint;
};
type Construction = Readonly<{inspect<Result>(project: () => Result): Result}>;
type TableFacts = Readonly<{nodes: bigint; wire: bigint; strings: bigint; serializerText: bigint; then?: never}>;
type InspectSelector = (selector: unknown, inspect: (profile: unknown) => TableFacts) => TableFacts;
type DuckDBProfile = Pick<ReturnType<typeof checkInstalledDuckDBSourceProfile>,
  'database' | 'schema' | 'table' | 'sourceRef' | 'accountConfigurationWire'>;
type DuckDBEnvironment = Readonly<{body: Readonly<{connector_catalogs: readonly unknown[]}>}>;

type PhysicalConstructionPorts<Owner, Material> = Readonly<{
  fail(code: string): never;
  sourceCall: {
    (original: Owner, material: Material, name: 'InstalledTableConstructionInventory',
      args: readonly [nodes: bigint, wire: bigint, strings: bigint, serializerText: bigint]):
        readonly [nodes: bigint, text: bigint, wire: bigint];
    (original: Owner, material: Material, name: 'InstalledSourceConstructionCapacity',
      args: readonly [retainedNodes: bigint, retainedText: bigint, retainedWire: bigint,
        workspaceNodes: bigint, workspaceText: bigint, workspaceWire: bigint]): unknown;
  };
  reserveSource(original: Owner, material: Material, nodes: bigint, text: bigint, wire: bigint): unknown;
}>;

export function createInstalledSourcePhysicalConstruction<Owner extends Original, Material extends MaterialInventory>(
  {fail, sourceCall, reserveSource}: PhysicalConstructionPorts<Owner, Material>) {
  // The original profile constructor funds this SAME descriptor/stack/Set walk
  // before it allocates. No reader's completed parser workspace backs it.
  function inspectInstalledTableConstruction(profile: unknown) {
    let nodes = 0n, wire = 0n, strings = 0n, serializerText = 0n;
    const pending = [{value: profile, depth: 0n}], seen = new Set<object>();
    while (pending.length !== 0) {
      const {value, depth} = pending.pop()!;
      nodes++;
      let syntax;
      if (value === null) syntax = 4n;
      else if (typeof value === 'boolean') syntax = 5n;
      else if (typeof value === 'number' && Number.isFinite(value)) syntax = 25n;
      else if (typeof value === 'string') {
        strings += BigInt(value.length);
        syntax = 6n * BigInt(value.length) + 2n;
      } else {
        if (!value || typeof value !== 'object' || nodeTypes.isProxy(value) || seen.has(value)) {
          fail('InvalidInstalledSourceProfileConstruction');
        }
        seen.add(value as object);
        const array = Array.isArray(value), fields = Object.getOwnPropertyDescriptors(value);
        if (!array && Object.getPrototypeOf(value) !== Object.prototype && Object.getPrototypeOf(value) !== null) {
          fail('InvalidInstalledSourceProfileConstruction');
        }
        syntax = 2n;
        for (const key of Reflect.ownKeys(fields)) {
          if (array && key === 'length') continue;
          const field = fields[key as keyof typeof fields];
          if (typeof key !== 'string' || !Object.hasOwn(field, 'value')) fail('InvalidInstalledSourceProfileConstruction');
          if (field.value === undefined) continue;
          syntax++;
          if (!array) {
            strings += BigInt((key as string).length);
            syntax += 6n * BigInt((key as string).length) + 3n;
            nodes++;
          }
          pending.push({value: field.value, depth: depth + 1n});
        }
      }
      wire += syntax;
      // Recursive canonical writers retain child strings while assembling
      // each ancestor. This sums actual input depths rather than maxDepth*wire.
      serializerText += syntax * (depth + 1n);
    }
    return Object.freeze({nodes, wire, strings, serializerText});
  }

  function reserveInstalledTableConstruction(original: Owner, material: Material, profile: unknown,
    construction: Construction | undefined) {
    if (typeof construction?.inspect !== 'function') fail('InstalledSourceProfileConstructionUnavailable');
    const facts = construction!.inspect(() => inspectInstalledTableConstruction(profile));
    const [allNodes, allText, allWire] = sourceCall(original, material,
      'InstalledTableConstructionInventory', [facts.nodes, facts.wire, facts.strings, facts.serializerText]);
    reserveSource(original, material, allNodes, allText, allWire);
    // Keep the entire original construction peak for failed or escaped pure
    // projections; do not infer that a provider's return settled its aliases.
    material.inputs.push(profile);
    material.nodes += allNodes; material.text += allText; material.wire += allWire;
    // Return constructor DATA; the selected RowRun still reserves its own copies.
    return sourceCall(original, material, 'InstalledSourceConstructionCapacity',
      [allNodes, allText, allWire, allNodes, allText, allWire]);
  }

  function installedTableReaderConstruction(original: Owner, material: Material,
    profile: Readonly<{targets: readonly Readonly<{selector: unknown}>[]}>, construction: Construction, bridge: object) {
    const field = Object.getOwnPropertyDescriptor(bridge, 'inspectReadSelectorConstruction');
    if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function' ||
        nodeTypes.isProxy(field.value) || nodeTypes.isAsyncFunction(field.value)) {
      fail('InstalledTableSourceConstructionUnavailable');
    }
    const facts = construction.inspect(() => {
      const maximum = {nodes: 0n, wire: 0n, strings: 0n, serializerText: 0n};
      for (const target of profile.targets) {
        const next = Reflect.apply(field!.value as InspectSelector, bridge, [target.selector, inspectInstalledTableConstruction]);
        for (const key of ['nodes', 'wire', 'strings', 'serializerText'] as const) {
          if (next[key] > maximum[key]) maximum[key] = next[key];
        }
      }
      return Object.freeze(maximum);
    });
    const [nodes, text, wire] = sourceCall(original, material, 'InstalledTableConstructionInventory',
      [facts.nodes, facts.wire, facts.strings, facts.serializerText]);
    return sourceCall(original, material, 'InstalledSourceConstructionCapacity',
      [nodes, text, wire, nodes, text, wire]);
  }

  // The checked Environment owns its complete parse/native projection already.
  // Account admission occurs once; each existing connector-binding digest uses
  // the same physical-target projection. Keep their input-proportional controls,
  // UTF-8/hex strings and serialization overlap before either constructor. These
  // are the existing Source node/text/byte quantities, never numerical admission.
  function reserveInstalledDuckDBConstruction(original: Owner, material: Material,
    profile: DuckDBProfile, environment: DuckDBEnvironment) {
    const bindings = BigInt(environment.body.connector_catalogs.length);
    const physicalUnits = BigInt(profile.database.length) + BigInt(profile.schema.length) + BigInt(profile.table.length);
    // Physical target retains original names plus at most eight hex units per
    // UTF-16 input unit. Root/principal/source names belong to each exact digest.
    const bindingUnits = 9n * physicalUnits + BigInt(original.root.length) +
      BigInt(original.principalId.length) + BigInt(profile.sourceRef.length);
    const units = BigInt(profile.accountConfigurationWire.length) + bindings * bindingUnits;
    const operations = 1n + bindings;
    const nodes = 16n * (units + operations), text = 16n * units, wire = 8n * units;
    reserveSource(original, material, nodes, text, wire);
    // Failed constructors retain their complete admitted peak on this SAME
    // Source successor. No return from a pure wrapper is a cleanup receipt.
    material.inputs.push(profile, environment);
    material.nodes += nodes; material.text += text; material.wire += wire;
  }

  return {reserveInstalledTableConstruction, installedTableReaderConstruction, reserveInstalledDuckDBConstruction};
}
