// Authored Command DATA composition inside the existing bound initializer.
// Validation, authority and currentness remain with the original Common owners.
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {canonicalJson} from './local-account-config.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {sourceEnvironmentCompositionGeometry} from './installed-source-construction-geometry.mjs';
const fail = () => {throw new TypeError('InvalidInstalledAuthoredCommand');};
const cid = value => 'sha256:' + createHash('sha256').update(canonicalJson(value)).digest('hex');

export function authoredCommandProjection(moon, specification) {
  if (!specification || nodeTypes.isProxy(specification) || !Object.isFrozen(specification)) fail();
  const own = (value, keys) => {
    if (!value || nodeTypes.isProxy(value) || !Object.isFrozen(value)) fail();
    const fields = Object.getOwnPropertyDescriptors(value);
    if (Reflect.ownKeys(fields).length !== keys.length || keys.some(key =>
      !Object.hasOwn(fields[key] ?? {}, 'value'))) fail();
    return Object.fromEntries(keys.map(key => [key, fields[key].value]));
  };
  const {operation, commands, contracts} = own(specification, ['operation', 'commands', 'contracts']);
  if (typeof operation !== 'string' || !operation || !operation.isWellFormed() ||
      !Array.isArray(commands) || nodeTypes.isProxy(commands) || !Object.isFrozen(commands) || commands.length === 0 ||
      !Array.isArray(contracts) || nodeTypes.isProxy(contracts) || !Object.isFrozen(contracts)) fail();
  const entries = values => {
    const fields = Object.getOwnPropertyDescriptors(values);
    if (Reflect.ownKeys(fields).length !== values.length + 1 ||
        Array.from({length: values.length}, (_, index) => String(index)).some(key =>
          !Object.hasOwn(fields[key] ?? {}, 'value'))) fail();
    return Array.from({length: values.length}, (_, index) => fields[index].value);
  };
  const captured = entries(commands).map(value => {
    const selected = own(value, ['resource', 'body']);
    if (typeof selected.resource !== 'string' || !selected.resource || typeof selected.body !== 'string') fail();
    return Object.freeze(selected);
  });
  const roles = Object.freeze(entries(contracts));
  for (const body of roles) if (typeof body !== 'string') fail();
  const definition = Object.freeze({kind: 'command', memberOperations: Object.freeze([]),
    rowOperations: Object.freeze([Object.freeze({role: 'write', operation})])});
  return Object.freeze({
    capacity(wire) {
      const geometry = sourceEnvironmentCompositionGeometry([wire,
        ...captured.map(value => value.body), ...roles]);
      return checked(moon.clientProgramInstalledSourceConstructionCapacity(
        geometry.retained.nodes, geometry.retained.text, geometry.retained.wire,
        geometry.nodes, geometry.text, geometry.wire));
    },
    project(wire) {
      const original = JSON.parse(wire), catalog = JSON.parse(original.catalog);
      const bodies = captured.map(value => JSON.parse(value.body));
      const added = roles.map(body => JSON.parse(body));
      for (const [index, body] of bodies.entries()) {
        const {contract_cid, ...preimage} = body;
        if (typeof body.command_id !== 'string' || cid(preimage) !== contract_cid ||
            body.connector_id !== catalog.connector_id) fail();
        if (bodies.slice(0, index).some(prior => prior.command_id === body.command_id)) fail();
      }
      for (const body of added) {
        const {cid: self, ...preimage} = body;
        if (cid(preimage) !== self) fail();
      }
      const {catalog_cid: _, ...preimage} = catalog;
      const byCid = new Map([...catalog.contracts, ...added].map(value => [value.cid, value]));
      const completed = {...preimage, commands: [...catalog.commands, ...bodies],
        contracts: [...byCid.values()].sort((left, right) => left.cid.localeCompare(right.cid))};
      const declared = {...original, catalog_cid: cid(completed),
        catalog: canonicalJson({...completed, catalog_cid: cid(completed)}),
        contracts: completed.contracts.map(value => canonicalJson(value)),
        command_bodies: [...(original.command_bodies ?? []), ...captured.map(value => value.body)]};
      return Object.freeze({declared, wire: canonicalJson(declared), definition,
        commands: captured.map((value, index) => ({resource: value.resource,
          commandRef: bodies[index].command_id, commandCid: bodies[index].contract_cid, body: value.body}))});
    },
  });
}
