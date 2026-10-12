// Test-only projection of frozen authored source syntax. This never invokes a
// parser/compiler/runtime, transforms a submitted request, or edits JSON data.
// Only the installed FieldRef/OutputName positions change their notation.
export const sgaRoleFixtureFamilies = new Set([
  'graph-match-source-input', 'graph-traverse-path-source-input',
  'graph-traverse-source-input', 'graph-reach-source-input',
  'graph-shortest-source-input', 'subgraph-source-input',
  'graph-delta-source-input', 'graph-delta-json-source',
]);
export function sgaRoleSourceOracle(text) {
  const quoted = value => '`' + value + '`';
  return text.replace(/\b(id|field|weight): (['"])([^'"]+)\2/giu,
    (_all, key, _quote, value) => key + ': ' + quoted(value))
    .replace(/\b(fields): \[([^\]]*)\]/giu, (_all, key, fields) =>
      key + ': [' + fields.replace(/['"]([^'"]+)['"]/gu,
        (_field, value) => quoted(value)) + ']')
    .replace(/(\bbindings:\s*\{)([^}]*)(\})/giu, (_all, head, fields, tail) =>
      head + fields.replace(/((?:`[^`]+`|\w+): )(['"])([^'"]+)\2/gu,
        (_binding, key, _quote, value) => key + quoted(value)) + tail);
}
