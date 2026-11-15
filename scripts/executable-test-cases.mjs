// Stable references identify actual canonical MoonBit test declarations.
// They do not establish execution, coverage, resource funding or authority.
export function hasExecutableTestCase(source, id) {
  if (typeof id !== 'string' || !/^[a-z][a-z0-9_]*$/u.test(id)) return false;
  // A commented example is not an executable declaration. Raw-string lines
  // are single lexical units, so their comment delimiters cannot hide code.
  const hidden = [...source.matchAll(/^[ \t]*#\|[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])'|\/\/[^\n]*|\/\*[\s\S]*?\*\//gmu)];
  const cases = [...source.matchAll(/^test "(?:[^"\\\n]|\\.)+" \{\r?\n  \/\/ resource-case-id: ([a-z][a-z0-9_]*)\r?\n/gmu)];
  let cursor = 0, found = 0;
  for (const match of cases) {
    while (cursor < hidden.length && hidden[cursor].index + hidden[cursor][0].length <= match.index) cursor++;
    if (hidden[cursor]?.index <= match.index) continue;
    if (match[1] === id) found++;
  }
  return found === 1;
}
