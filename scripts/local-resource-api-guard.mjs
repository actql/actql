import path from 'node:path';

const sorterPackage = 'actql/actql/bounded_tuple_sort';

// A small lexical guard for these APIs, not a MoonBit type checker. Literal
// text is opaque; interpolation expressions remain code. Retain punctuation
// so whitespace cannot hide references. This regression check does not prove
// language semantics or replace compilation and bounded execution tests.
function tokens(source) {
  const result = [];
  const identifier = /[A-Za-z_][A-Za-z_0-9]*/y;
  let index = 0;
  const literal = () => result.push({kind: 'literal'});
  const interpolation = () => {
    result.push({kind: 'code', value: '{'});
    index += 2;
    scan(true);
    literal();
  };
  const scan = (untilBrace = false) => {
    let depth = 0;
    while (index < source.length) {
      const start = index;
      const pair = source.slice(index, index + 2);
      if (/\s/u.test(source[index])) {
        index++;
      } else if (pair === '//' || pair === '#|') {
        const end = source.indexOf('\n', index);
        index = end < 0 ? source.length : end;
      } else if (pair === '$|') {
        literal();
        index += 2;
        while (index < source.length && source[index] !== '\n') {
          if (source.slice(index, index + 2) === '\\{') interpolation();
          else index += source[index] === '\\' ? 2 : 1;
        }
      } else if (pair === '/*') {
        let nesting = 1;
        index += 2;
        while (index < source.length && nesting > 0) {
          const next = source.slice(index, index + 2);
          if (next === '/*') nesting++;
          if (next === '*/') nesting--;
          index += next === '/*' || next === '*/' ? 2 : 1;
        }
      } else if (source[index] === '"' || source[index] === "'") {
        const quote = source[index++];
        const token = {kind: 'literal'};
        result.push(token);
        while (index < source.length) {
          if (source[index] === quote) { index++; break; }
          if (quote === '"' && source.slice(index, index + 2) === '\\{') interpolation();
          else index += source[index] === '\\' ? 2 : 1;
        }
        if (quote === '"') {
          try { token.value = JSON.parse(source.slice(start, index)); } catch { /* Not an import string. */ }
        }
      } else {
        identifier.lastIndex = index;
        const word = identifier.exec(source);
        const value = word ? word[0] : source[index];
        result.push({kind: 'code', value});
        index += value.length;
        if (value === '{') depth++;
        if (value === '}') {
          if (untilBrace && depth === 0) return;
          depth--;
        }
      }
    }
  };
  scan();
  return result;
}

function is(token, value) {
  return token?.kind === 'code' && token.value === value;
}

function closingBrace(items, start) {
  let depth = 1;
  let end = start + 1;
  for (; end < items.length && depth > 0; end++) {
    if (is(items[end], '{')) depth++;
    if (is(items[end], '}')) depth--;
  }
  return end;
}

export function boundedSorterAliases(packageSource) {
  const aliases = new Set();
  const items = tokens(packageSource);
  for (let index = 0; index < items.length; index++) {
    if (!is(items[index], 'import') || !is(items[index + 1], '{')) continue;
    const end = closingBrace(items, index + 1);
    const testOnly = is(items[end], 'for') &&
      ['test', 'wbtest'].includes(items[end + 1]?.value);
    if (!testOnly) {
      for (let entry = index + 2; entry < end - 1; entry++) {
        if (items[entry].kind !== 'literal' || items[entry].value !== sorterPackage) continue;
        aliases.add(is(items[entry + 1], '@')
          ? items[entry + 2]?.value : 'bounded_tuple_sort');
      }
    }
    index = end - 1;
  }
  return aliases;
}

export function isProductionMoonSource(file) {
  return file.endsWith('.mbt') && !/_(?:wb|bb)?test\.mbt$/u.test(file);
}

function productionTokens(source) {
  const items = tokens(source);
  const result = [];
  let depth = 0;
  for (let index = 0; index < items.length; index++) {
    if (depth === 0 && is(items[index], 'test')) {
      const body = items[index + 1]?.kind === 'literal' ? index + 2 : index + 1;
      if (is(items[body], '{')) {
        index = closingBrace(items, body) - 1;
        continue;
      }
    }
    if (is(items[index], '{')) depth++;
    if (is(items[index], '}')) depth--;
    result.push(items[index]);
  }
  return result;
}

function hasRequiredWorkspace(source, name) {
  const items = productionTokens(source);
  const start = items.findIndex((item, index) => is(item, 'pub') &&
    is(items[index + 1], 'fn') && is(items[index + 2], name) && is(items[index + 3], '('));
  if (start < 0) return false;
  let depth = 0;
  let parameter = [];
  for (let index = start + 4; index < items.length; index++) {
    const item = items[index];
    if (depth === 0 && (is(item, ',') || is(item, ')'))) {
      if (is(parameter[0], 'external_workspace_slots')) {
        return parameter.length === 4 && is(parameter[1], '~') &&
          is(parameter[2], ':') && is(parameter[3], 'Int');
      }
      if (is(item, ')')) return false;
      parameter = [];
      continue;
    }
    if (item.kind === 'code' && ['(', '[', '{'].includes(item.value)) depth++;
    if (item.kind === 'code' && [')', ']', '}'].includes(item.value)) depth--;
    parameter.push(item);
  }
  return false;
}

// Consumes only caller-owned snapshot bytes. Discovery and filesystem reads
// belong to loadResourceAccountingSources, never to this validator helper.
export function localResourceApiIssues({root, sources}) {
  const issues = [];
  for (const [relative, name] of [
    ['src/managed_record_storage/append_steps.mbt', 'start_append'],
    ['src/managed_record_runtime/output.mbt', 'start_record_append'],
  ]) {
    if (!hasRequiredWorkspace(sources[path.resolve(root, relative)]?.text ?? '', name)) {
      issues.push(`${relative}: ${name} must require external_workspace_slots~ : Int without a default`);
    }
  }
  const packages = new Map();
  for (const [file, source] of Object.entries(sources)) {
    if (path.basename(file) !== 'moon.pkg' || !source.exists || !source.text) continue;
    const aliases = boundedSorterAliases(source.text);
    if (aliases.size) packages.set(path.dirname(file), aliases);
  }
  for (const [file, source] of Object.entries(sources)) {
    const aliases = packages.get(path.dirname(file));
    if (!aliases || !source.exists || !isProductionMoonSource(file)) continue;
    const items = productionTokens(source.text);
    for (let index = 0; index < items.length - 3; index++) {
      if (is(items[index], '@') && aliases.has(items[index + 1]?.value) &&
          is(items[index + 2], '.') && is(items[index + 3], 'prepare')) {
        issues.push(`${path.relative(root, file)}: eager bounded_tuple_sort.prepare reference; bounded consumers must use prepare_deferred`);
        break;
      }
    }
  }
  return issues;
}
