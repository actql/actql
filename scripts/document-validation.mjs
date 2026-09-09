import assert from 'node:assert/strict';
import { readdirSync, existsSync, readFileSync } from 'node:fs';
import { resolve, dirname, extname } from 'node:path';
import { unified } from 'unified';
import remarkParse from 'remark-parse';
import { parseDocument } from 'yaml';
import GithubSlugger from 'github-slugger';

export function walk(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    if (['.git', 'node_modules', '__pycache__', '_build', 'target'].includes(entry.name)) return [];
    const path = `${dir}/${entry.name}`;
    return entry.isDirectory() ? walk(path) : [path];
  });
}
export const nodes = node => [node, ...(node.children ?? []).flatMap(nodes)];
export const markdown = source => unified().use(remarkParse).parse(source);
export function validateProgramLayout(value, label) {
  assert.equal(value.version, 'actql/0.1', `${label}: unsupported version`);
  assert.ok(Array.isArray(value.stages) && value.stages.length > 0, `${label}: Program requires nonempty stages`);
  for (const key of ['inputs', 'from', 'steps', 'effects']) assert.ok(!(key in value), `${label}: ${key} is stage-local`);
}
export function validateExamples(discovered, documents) {
  const registered = new Set();
  for (const document of documents) for (const example of document.programs) {
    const key = `${document.path}#${example.id}`;
    assert.ok(!registered.has(key), `Duplicate manifest entry ${key}`);
    registered.add(key);
    assert.ok(discovered.has(key), `Missing example ${key}`);
    assert.ok(['valid', 'invalid'].includes(example.expected_status), `Invalid expectation ${key}`);
    if (example.expected_status === 'valid') validateProgramLayout(discovered.get(key), key);
    else assert.ok(typeof example.expected_diagnostic === 'string' && example.expected_diagnostic.length, `Missing expected diagnostic ${key}`);
  }
  for (const key of discovered.keys()) assert.ok(registered.has(key), `Unregistered example ${key}`);
}
export function validateLocalLinks(file, source, anchorCache = new Map()) {
  const all = nodes(markdown(source));
  const definitions = new Map(all.filter(n => n.type === 'definition').map(n => [n.identifier, n.url]));
  let count = 0;
  for (const node of all.filter(n => ['link', 'image', 'linkReference', 'imageReference'].includes(n.type))) {
    const url = node.url ?? definitions.get(node.identifier);
    assert.ok(url, `${file}: unresolved link reference ${node.identifier}`);
    if (/^[a-z][a-z\d+.-]*:|^\/\//i.test(url)) continue;
    const [pathname, fragment] = url.split('#');
    const target = pathname ? resolve(dirname(file), decodeURIComponent(pathname.split('?')[0])) : resolve(file);
    assert.ok(existsSync(target), `Broken link: ${file} -> ${url}`);
    if (fragment && extname(target) === '.md') {
      if (!anchorCache.has(target)) anchorCache.set(target, anchors(markdown(readFileSync(target, 'utf8'))));
      assert.ok(anchorCache.get(target).has(decodeURIComponent(fragment)), `Broken anchor: ${file} -> ${url}`);
    }
    count++;
  }
  return count;
}
export function anchors(tree) {
  const slugger = new GithubSlugger();
  const result = new Set();
  for (const node of nodes(tree)) {
    if (node.type === 'heading') {
      const text = nodes(node).filter(n => ['text', 'inlineCode'].includes(n.type)).map(n => n.value).join('');
      result.add(slugger.slug(text));
    }
    if (node.type === 'html') for (const match of node.value.matchAll(/\b(?:id|name)=["']([^"']+)["']/g)) result.add(match[1]);
  }
  return result;
}
export function decodeYaml(source, label) {
  const document = parseDocument(source, { uniqueKeys: true });
  assert.equal(document.errors.length, 0, `${label}: ${document.errors.map(e => e.message).join('; ')}`);
  return document.toJS({ maxAliasCount: 100 });
}
export function programs(source, path) {
  const blocks = path.endsWith('.aql') ? [source] : nodes(markdown(source))
    .filter(n => n.type === 'code' && ['yaml', 'yml', 'aql'].includes(n.lang)).map(n => n.value);
  return blocks.flatMap((block, i) => {
    // Incomplete grammar illustrations are not complete Program fixtures.
    if (!path.endsWith('.aql') && !/^version:\s*["']?actql\//m.test(block)) return [];
    const value = decodeYaml(block, `${path}, block ${i + 1}`);
    assert.ok(value && typeof value === 'object' && !Array.isArray(value), `${path}: expected a document object`);
    assert.ok(typeof value.id === 'string' && value.id.length, `${path}: example needs an id`);
    return [value];
  });
}
export function validateCases(cases, trace) {
  assert.ok(Array.isArray(cases.cases));
  const ids = new Set();
  for (const item of cases.cases) {
    for (const key of ['case_id', 'given', 'when', 'then']) assert.ok(typeof item[key] === 'string' && item[key].trim(), `Missing ${key}`);
    assert.ok(!ids.has(item.case_id), `Duplicate case ${item.case_id}`);
    ids.add(item.case_id);
  }
  for (const item of [...trace.decisions, ...trace.maintained, ...(trace.additional_questions ?? [])]) {
    for (const id of [...(item.acceptance_cases ?? []), ...(item.case_ids ?? [])]) assert.ok(ids.has(id), `Missing acceptance case ${id}`);
  }
  return ids.size;
}
