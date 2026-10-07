// Local diagnostic compilation only. Keep every non-test declaration byte for
// byte; this projection neither deletes repository tests nor authorizes reuse.
import assert from 'node:assert/strict';
import {hash} from '../../inventory.mjs';

function tokens(source) {
  const result = [];
  let i = 0;
  const comment = () => {
    if (source.startsWith('//', i)) {
      const end = source.indexOf('\n', i); i = end < 0 ? source.length : end; return true;
    }
    if (!source.startsWith('/*', i)) return false;
    i += 2; let depth = 1;
    while (i < source.length && depth) {
      if (source.startsWith('/*', i)) { depth++; i += 2; }
      else if (source.startsWith('*/', i)) { depth--; i += 2; }
      else i++;
    }
    assert.equal(depth, 0, 'Unterminated compilation-input comment'); return true;
  };
  const rawLine = () => {
    assert(!source.startsWith('$|', i), 'Unsupported interpolated raw line');
    if (!source.startsWith('#|', i)) return false;
    assert.match(source.slice(source.lastIndexOf('\n', i - 1) + 1, i), /^\s*$/, 'Ambiguous raw line');
    const end = source.indexOf('\n', i); i = end < 0 ? source.length : end; return true;
  };
  const quoted = quote => {
    assert.equal(source[i++], quote);
    while (i < source.length) {
      if (source[i] === quote) { i++; return; }
      assert(source[i] !== '\n' && source[i] !== '\r', 'Unterminated compilation-input literal');
      if (source[i++] === '\\') {
        assert(i < source.length, 'Unterminated compilation-input escape');
        if (quote === '"' && source[i] === '{') interpolation();
        else i++;
      }
    }
    assert.fail('Unterminated compilation-input literal');
  };
  const interpolation = () => {
    assert.equal(source[i++], '{'); let depth = 1;
    while (i < source.length && depth) {
      if (comment() || rawLine()) continue;
      if (source[i] === '"' || source[i] === "'") { quoted(source[i]); continue; }
      if (source[i] === '{') depth++;
      else if (source[i] === '}') depth--;
      i++;
    }
    assert.equal(depth, 0, 'Unterminated compilation-input interpolation');
  };
  while (i < source.length) {
    if (/\s/.test(source[i]) || comment() || rawLine()) { if (/\s/.test(source[i] ?? '')) i++; continue; }
    const begin = i;
    if (source[i] === '"' || source[i] === "'") {
      quoted(source[i]); result.push({value: 'literal', begin, end: i}); continue;
    }
    if (/[A-Za-z_]/.test(source[i])) {
      while (i < source.length && /[A-Za-z0-9_]/.test(source[i])) i++;
    } else i++;
    result.push({value: source.slice(begin, i), begin, end: i});
  }
  return result;
}

export function omitUnselectedTests(source) {
  const ts = tokens(source), omitted = [];
  let depth = 0;
  for (let i = 0; i < ts.length; i++) {
    const t = ts[i];
    assert(!(depth === 0 && t.value === '#' && ts[i+1]?.value === '['), 'Unsupported declaration attribute');
    if (t.value === 'test' && depth === 0) {
      assert.match(source.slice(source.lastIndexOf('\n', t.begin - 1) + 1, t.begin), /^\s*$/, 'Ambiguous test declaration');
      let open = i + 1;
      if (ts[open]?.value === 'literal') open++;
      assert.equal(ts[open]?.value, '{', 'Unsupported test declaration');
      let d = 1, close = open + 1;
      for (; close < ts.length && d; close++) {
        if (ts[close].value === '{') d++;
        else if (ts[close].value === '}') d--;
      }
      assert.equal(d, 0, 'Unterminated test declaration');
      const end = ts[close - 1].end;
      omitted.push({begin: t.begin, end, digest: hash(source.slice(t.begin, end))});
      i = close - 1;
    } else {
      if (t.value === '{') depth++;
      else if (t.value === '}') depth--;
      assert(depth >= 0, 'Unbalanced compilation input');
    }
  }
  assert.equal(depth, 0, 'Unbalanced compilation input');
  // Preserve offsets, newlines and every byte outside an omitted test range.
  let text = '', end = 0;
  for (const range of omitted) {
    text += source.slice(end, range.begin) + source.slice(range.begin, range.end).replace(/[^\r\n]/g, ' ');
    end = range.end;
  }
  text += source.slice(end);
  return {text, omitted, originalDigest: hash(source), projectedDigest: hash(text)};
}

export function retirementCompilation(read, source, overlay) {
  assert(source.sources, 'Compilation requires the original directory inventory');
  const paths = Object.keys(source.sources).filter(p => /^src\/query_integration\/[^/]+_wbtest\.mbt$/.test(p)).sort();
  assert(paths.length > 0, 'Missing existing Host whitebox input inventory');
  const inputs = {};
  for (const path of paths) {
    const original = read(path).toString();
    assert.equal(hash(original), source.sources[path], 'Changed compilation source '+path);
    const observed = overlay[path] ?? original;
    const projection = omitUnselectedTests(observed);
    overlay[path] = projection.text;
    inputs[path] = {offsetUnit: 'utf16-code-unit', sourceDigest: hash(original), observedDigest: projection.originalDigest,
      projectedDigest: projection.projectedDigest, omitted: projection.omitted};
  }
  return {scope: 'one selected Native Host fixture; all existing non-test declarations retained',
    inputs, omittedTests: Object.values(inputs).reduce((n, input) => n + input.omitted.length, 0),
    repositoryTestsRemoved: false, reuseAuthorized: false};
}
