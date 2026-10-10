// The registered machine contracts own Python DTOs as well as JS/Native DTOs.
import {readFile, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {join, resolve} from 'node:path';
import {project} from './generate-client-publication-wire.mjs';
import {responseRules, requestResponseRules} from './generate-native-client-wire.mjs';
import {checkReportRules} from './client-check-report-rules.mjs';
import {clientSourceFormats, checkpointLimits, resultDescriptionLimits} from '../packages/client-wire/index.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
export function pythonClientContract(registry, protocol, publication, reasons) {
  if (registry.version !== 'actql-client-host/0.1') throw Error('InvalidPythonClientContract');
  const schemas = Object.fromEntries(Object.entries(registry.schemas).map(([name, schema]) => [name, project(schema)]));
  for (const name of ['run_state', 'check_outcome']) schemas[name] = project(protocol.artifact_schemas[name]);
  schemas.value_contract = project(protocol.schemas.canonical_value_contract.$defs.value_contract);
  for (const name of ['delivery_attempt', 'delivery_record']) schemas[name] = project(publication.schemas[name]);
  schemas.result_delivery_receipt = project(protocol.artifact_schemas.result_delivery_receipt);
  return {version: registry.version, operations: registry.operations, schemas,
    source_formats: clientSourceFormats, checkpoint_limits: checkpointLimits,
    result_description_limits: resultDescriptionLimits,
    response_rules: responseRules(registry), request_response_rules: requestResponseRules(registry, schemas),
    check_report_rules: checkReportRules(registry),
    check_reason_schema_cid: protocol.artifact_schema_cids.check_reason,
    check_outcome_schema_cid: protocol.artifact_schema_cids.check_outcome,
    reasons};
}

export function pythonTypes(schemas) {
  const declarations = [];
  const identifier = value => value.split(/[^a-zA-Z0-9]+/u).filter(Boolean)
    .map(part => part[0].toUpperCase() + part.slice(1)).join('');
  const literal = value => value === true ? 'True' : value === false ? 'False' :
    value === null ? 'None' : JSON.stringify(value);
  function type(schema, path) {
    if (schema.$ref) return identifier(schema.$ref);
    if (schema.oneOf) return schema.oneOf.map((rule, index) => type(rule, path + index)).join(' | ');
    if (Object.hasOwn(schema, 'const')) return schema.const === null ? 'None' : `Literal[${literal(schema.const)}]`;
    if (schema.enum) return `Literal[${schema.enum.map(literal).join(', ')}]`;
    if (schema.type === 'string') return 'str';
    if (schema.type === 'number') return 'int | float';
    if (schema.type === 'integer') return 'int';
    if (schema.type === 'boolean') return 'bool';
    if (schema.type === 'array') return `list[${type(schema.items, path + 'Item')}]`;
    if (schema.type === 'object') {
      if (!schema.properties) return `dict[str, ${typeof schema.additionalProperties === 'object'
        ? type(schema.additionalProperties, path + 'Value') : 'Any'}]`;
      const fields = Object.entries(schema.properties).map(([key, value]) =>
        `${JSON.stringify(key)}: ${schema.required?.includes(key) ? 'Required' : 'NotRequired'}[${type(value, path + identifier(key))}]`);
      declarations.push(`${path} = TypedDict(${JSON.stringify(path)}, {${fields.join(', ')}}, total=False)`);
      return path;
    }
    return 'Any';
  }
  for (const [name, schema] of Object.entries(schemas)) {
    const alias = identifier(name);
    const result = type(schema, alias);
    if (result !== alias) declarations.push(`${alias} = ${result}`);
  }
  // Quoted annotations allow schema references to later DTO declarations.
  return '# Generated from registered ActQL contracts; do not edit.\n' +
    'from __future__ import annotations\nfrom typing import Any, Literal, NotRequired, Required, TypedDict\n\n' +
    declarations.map(line => line.replace(/(Required|NotRequired)\[([^\n]*?)\](?=, "|\}, total)/gu,
      (_, wrapper, expression) => `${wrapper}[${JSON.stringify(expression)}]`)).join('\n\n') + '\n';
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length !== 1 || !['--write', '--check'].includes(args[0])) throw Error('Usage: generate-python-client-wire.mjs --write|--check');
  const read = async path => JSON.parse(await readFile(join(root, path), 'utf8'));
  const contract = pythonClientContract(await read('spec/contracts/actql-client-host.json'),
    await read('spec/contracts/actql-protocol-schemas.json'), await read('spec/contracts/actql-run-publication.json'),
    await read('spec/contracts/actql-check-reason-catalog.json'));
  const outputs = {'_contract.json': JSON.stringify(contract, null, 2) + '\n', '_types.py': pythonTypes(contract.schemas)};
  for (const [file, content] of Object.entries(outputs)) {
    const path = join(root, 'packages/python-sdk/src/actql_sdk', file);
    if (args[0] === '--write') await writeFile(path, content);
    else if (await readFile(path, 'utf8') !== content) throw Error(`StalePythonClientContract:${file}`);
  }
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
