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

export function connectorDispatchViolations(source, connectorNames) {
  const names = new Set([...connectorNames, 'native']);
  const variants = new Set(['Local', 'DuckDB', 'Native', ...connectorNames.map(name =>
    name.split(/[_-]/).map(part => part[0].toUpperCase() + part.slice(1)).join(''))]);
  const pattern = /\/\/[^\n]*|\/\*[\s\S]*?\*\/|"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*'|`(?:\\[\s\S]|[^`\\])*`|[A-Za-z_][A-Za-z0-9_]*|[^\s]/g;
  const tokens = [...source.matchAll(pattern)].filter(match =>
    !match[0].startsWith('//') && !match[0].startsWith('/*'));
  const violations = [];
  for (let index = 0; index < tokens.length; index++) {
    const match = tokens[index];
    const token = match[0];
    const literal = /^["'`]/.test(token);
    if ((literal && names.has(literalValue(token).toLowerCase())) ||
        (!literal && variants.has(token)) ||
        (!literal && names.has(token) && (tokens[index + 1]?.[0] === ':' || tokens[index - 1]?.[0] === '@'))) {
      violations.push({line: source.slice(0, match.index).split('\n').length, token});
    }
  }
  return violations;
}

export function checkConnectorDispatchBoundary(root) {
  const connectors = readdirSync(join(root, 'src/connectors'), {withFileTypes: true})
    .filter(entry => entry.isDirectory()).map(entry => entry.name);
  const roots = ['src/connector_sdk', 'src/query_planning', 'src/physical_host',
    'src/physical_strategy', 'src/physical_resources', 'src/physical_cost', 'adapters/host-node',
    'adapters/host-common',
    'scripts/templates'];
  const failures = [];
  let count = 0;
  function inspect(directory) {
    for (const entry of readdirSync(join(root, directory), {withFileTypes: true})) {
      if (entry.isDirectory()) { inspect(directory + '/' + entry.name); continue; }
      if (!entry.isFile() || !/\.(mbt|mjs)$/.test(entry.name) || /(?:_test|_wbtest|_bbtest|\.test)\./.test(entry.name)) continue;
      const path = directory + '/' + entry.name;
      // The installed Local Host is a concrete adapter, not shared dispatch.
      if (path === 'adapters/host-node/embedded-local.mjs') continue;
      count += 1;
      for (const violation of connectorDispatchViolations(readFileSync(join(root, path), 'utf8'), connectors)) {
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
