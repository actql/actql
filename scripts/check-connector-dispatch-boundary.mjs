// A source-level regression gate, complemented by dependency/API checks and
// isolated builds. This is not a sandbox or proof against deliberately obfuscated
// plugin code. Common dispatch must not encode concrete implementation IDs.
import {readFileSync, readdirSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

function literalValue(token) {
  return token.slice(1, -1).replace(/\\(?:u\{([0-9a-fA-F]+)\}|u([0-9a-fA-F]{4})|x([0-9a-fA-F]{2})|(.))/gs,
    (_whole, point, unit, byte, escaped) => point || unit || byte
      ? String.fromCodePoint(parseInt(point ?? unit ?? byte, 16))
      : ({n: '\n', r: '\r', t: '\t', b: '\b', f: '\f', v: '\v', '0': '\0'}[escaped] ?? escaped));
}

function sourceTokens(source) {
  const pattern = /\/\/[^\n]*|\/\*[\s\S]*?\*\/|"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*'|`(?:\\[\s\S]|[^`\\])*`|[A-Za-z_][A-Za-z0-9_]*|[^\s]/g;
  return [...source.matchAll(pattern)].filter(match =>
    !match[0].startsWith('//') && !match[0].startsWith('/*'));
}

// These closed checks admit measurement conditions; their only branch is
// PolicyWireStop. Observation scope is a copied-metadata default, never a
// connector selector. Match the complete tokenized statement, not the file or
// every occurrence of a label.
// Fixed intrinsic captures name a Node filesystem operation, not a Connector.
// Include the original descriptor/object bindings in the exact statement match;
// changing a callee/object/property or adding a selector remains a violation.
const measurementChecks = new Map([
  ['adapters/host-node/client-request-journal.mjs', `
    const facilityDescriptor = Object.getOwnPropertyDescriptor;
    const facilityRealpath = realpathSync;
    const facilityNativeRealpath = facilityDescriptor(facilityRealpath, 'native')?.value;
  `],
  ['adapters/host-common/sqlite-format-inspection.mjs', `
    const originalRealpath = realpathSync;
    const originalNativeRealpath = Object.getOwnPropertyDescriptor(originalRealpath, 'native')?.value;
  `],
  ['src/physical_strategy_host/operational_conditions.mbt', `
    if value.host != "native" || value.concurrency != 1 || value.input_rows < 1 ||
      !["off", "metadata-only", "evidence-enabled"].contains(value.capture_mode) ||
      !["fresh", "resident"].contains(value.realization) { raise PolicyWireStop }
  `],
  ['src/physical_strategy_host/operational_estimates.mbt', `
    if !["off", "metadata-only", "evidence-enabled"].contains(
        policy_wire_text(conditions, "captureMode"),
      ) || !["fresh", "resident"].contains(
        policy_wire_text(conditions, "realization"),
      ) || policy_wire_text(conditions, "host") != "native" ||
      policy_wire_int(conditions, "concurrency") != 1 ||
      policy_wire_int(conditions, "inputRows") < 1 { raise PolicyWireStop }
  `],
  ['adapters/host-common/observation.mjs', `
    const {deliver, currentContext,
      scope = 'local', revision = 'metadata/0.1', limits = {},
      include = [...operations], exclude = [], correlation = true} = options;
  `],
]);

export function connectorDispatchViolations(source, connectorNames, relativePath = '') {
  const registrationNames = new Set(connectorNames);
  const names = new Set([...connectorNames, 'native']);
  const variants = new Set(['Local', 'DuckDB', 'Native', ...connectorNames.map(name =>
    name.split(/[_-]/).map(part => part[0].toUpperCase() + part.slice(1)).join(''))]);
  const tokens = sourceTokens(source);
  const measurementTokens = sourceTokens(measurementChecks.get(relativePath) ?? '');
  const measurementLabels = new Set();
  if (measurementTokens.length > 0) {
    for (let start = 0; start <= tokens.length - measurementTokens.length; start++) {
      if (measurementTokens.every((token, offset) => token[0] === tokens[start + offset][0])) {
        measurementTokens.forEach((token, offset) => {
          if (/^["'`]/u.test(token[0]) && names.has(literalValue(token[0]).toLowerCase())) {
            measurementLabels.add(start + offset);
          }
        });
      }
    }
  }
  const violations = [];
  for (let index = 0; index < tokens.length; index++) {
    const match = tokens[index];
    const token = match[0];
    if (measurementLabels.has(index)) continue;
    const literal = /^["'`]/.test(token);
    if ((literal && names.has(literalValue(token).toLowerCase())) ||
        (!literal && variants.has(token)) ||
        (!literal && registrationNames.has(token) && (tokens[index + 1]?.[0] === ':' || tokens[index - 1]?.[0] === '@'))) {
      violations.push({line: source.slice(0, match.index).split('\n').length, token});
    }
  }
  return violations;
}

export const isConnectorTestFixture = path => /(?:^|\/)fixtures\//u.test(path) ||
  /(?:\.|-)fixture\.mjs$/u.test(path);

export function checkConnectorDispatchBoundary(root) {
  const connectors = readdirSync(join(root, 'src/connectors'), {withFileTypes: true})
    .filter(entry => entry.isDirectory()).map(entry => entry.name);
  const roots = ['src/connector_sdk', 'src/query_planning', 'src/physical_host', 'src/physical_host_dispatch',
    'src/physical_strategy', 'src/physical_strategy_host', 'src/physical_resources', 'src/physical_cost', 'adapters/host-node',
    'adapters/host-common',
    'scripts/templates'];
  const failures = [];
  let count = 0;
  function inspect(directory) {
    for (const entry of readdirSync(join(root, directory), {withFileTypes: true})) {
      if (isConnectorTestFixture(directory + '/' + entry.name + (entry.isDirectory() ? '/' : ''))) continue;
      if (entry.isDirectory()) { inspect(directory + '/' + entry.name); continue; }
      if (!entry.isFile() || !/\.(mbt|mjs)$/.test(entry.name) || /(?:_test|_wbtest|_bbtest|\.test)\./.test(entry.name)) continue;
      const path = directory + '/' + entry.name;
      // The installed Local Host is a concrete adapter, not shared dispatch.
      if (path === 'adapters/host-node/embedded-local.mjs') continue;
      count += 1;
      const source = readFileSync(join(root, path), 'utf8');
      // Test-only custody does not exempt an implementation that imports it.
      for (const match of source.matchAll(/(?:\bfrom\s*|\bimport\s*(?:\(\s*)?|\brequire\s*\(\s*)(['"])([^'"]+\.mjs)\1/gu)) {
        if (isConnectorTestFixture(match[2])) failures.push({path, token: match[2], reason: 'test fixture imported by common implementation'});
      }
      for (const violation of connectorDispatchViolations(source, connectors, path)) {
        failures.push({path, ...violation});
      }
    }
  }
  for (const directory of roots) inspect(directory);
  if (failures.length) throw new Error('Concrete connector dispatch in common code: ' + JSON.stringify(failures));
  return count;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = fileURLToPath(new URL('../', import.meta.url));
  console.log(`${checkConnectorDispatchBoundary(root)} common implementation files have no concrete dispatch IDs.`);
}
