import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {posix} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const admissionPath = 'scripts/javascript-source-exceptions.json';
const javascriptExtension = /\.(?:js|cjs|mjs|jsx)$/iu;
const typedExtension = /\.(?:ts|cts|mts|tsx)$/iu;
const javascriptShebang = /^#![ \t]*(?:\S*\/)?(?:env[ \t]+(?:(?:-S|--split-string)[ \t]+)?)?(?:node|nodejs|bun|deno)(?:[ \t]|\r?$)/u;
const oid = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/u;
const roles = ['generated', 'third-party', 'consumer', 'negative-fixture'] as const;
const decoder = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true});

type Entry = {path: string; mode: string; object: string};
type Exception = Entry & {role: typeof roles[number]; owner: string; reason: string};

function git(root: string, args: string[], permittedStatus = 0) {
  const result = spawnSync('git', args, {cwd: root, timeout: 20_000, maxBuffer: 16 * 1024 * 1024});
  if (result.error) throw result.error;
  assert(result.signal === null && (result.status === 0 || result.status === permittedStatus),
    `Cannot read Git ${args[0]} inventory: ${result.stderr.toString('utf8')}`);
  return result.stdout;
}

function records(bytes: Buffer) {
  const contents = decoder.decode(bytes);
  if (!contents.length) return [];
  assert(contents.endsWith('\0'), 'Truncated Git source inventory');
  return contents.slice(0, -1).split('\0');
}

function repositoryPath(path: unknown): path is string {
  return typeof path === 'string' && path.length > 0 && !posix.isAbsolute(path) &&
    !/[\\\x00-\x1f\x7f]/u.test(path) && path.split('/').every(part => part !== '.' && part !== '..' && part !== '');
}

function regular(mode: unknown) { return mode === '100644' || mode === '100755'; }

function entries(root: string) {
  const args = ['ls-files', '--stage', '-z'];
  const result = new Map<string, Entry>();
  for (const row of records(git(root, args))) {
    const separator = row.indexOf('\t');
    const path = row.slice(separator + 1);
    assert(separator > 0 && repositoryPath(path), 'Invalid path in Git source inventory');
    const [mode, object, stage] = row.slice(0, separator).split(' ');
    assert(typeof mode === 'string' && /^[0-9]{6}$/u.test(mode) && typeof object === 'string' && oid.test(object),
      `Invalid object for ${path}`);
    assert(stage === '0' && !result.has(path), `Unmerged Git source entry: ${path}`);
    result.set(path, {path, mode, object});
  }
  return result;
}

function executableJavaScript(root: string, tracked: ReadonlyMap<string, Entry>) {
  const output = git(root, ['grep', '--cached', '--no-textconv', '-I', '-l', '-z', '-E', '-e',
    '^#!.*(node|nodejs|bun|deno)([[:space:]]|$)'], 1);
  const paths = new Set<string>();
  for (const path of records(output)) {
    if (javascriptExtension.test(path) || typedExtension.test(path)) continue;
    const entry = tracked.get(path);
    assert(entry && regular(entry.mode), `Invalid interpreter source entry: ${path}`);
    const contents = git(root, ['cat-file', 'blob', entry.object]);
    const newline = contents.indexOf(0x0a);
    const initial = contents.subarray(0, newline === -1 ? contents.length : newline).toString('utf8');
    if (javascriptShebang.test(initial)) paths.add(path);
  }
  return paths;
}

function readExemptions(root: string, tracked: ReadonlyMap<string, Entry>) {
  const manifest = tracked.get(admissionPath);
  assert(manifest && regular(manifest.mode), 'Tracked JavaScript source exceptions required');
  const raw: unknown = JSON.parse(decoder.decode(git(root, ['cat-file', 'blob', manifest.object])));
  assert(raw && typeof raw === 'object' && Object.keys(raw).length === 2 && 'version' in raw && raw.version === 1 &&
    'exemptions' in raw && Array.isArray(raw.exemptions), 'Invalid JavaScript source exceptions');
  const exemptions = raw.exemptions as Exception[];
  const paths = new Map<string, Exception>();
  let previous = '';
  for (const value of exemptions) {
    assert(value && typeof value === 'object' && Object.keys(value).length === 6 && repositoryPath(value.path) &&
      regular(value.mode) && typeof value.object === 'string' && oid.test(value.object) && roles.includes(value.role) &&
      repositoryPath(value.owner) && value.owner !== value.path && typeof value.reason === 'string' &&
      value.reason.trim().length > 0, 'JavaScript exceptions must name one exact tracked file, its owner and reason');
    assert(previous < value.path, `Unsorted or duplicate JavaScript source exception: ${value.path}`);
    assert(regular(tracked.get(value.owner)?.mode), `Missing tracked exception owner: ${value.owner}`);
    previous = value.path;
    paths.set(value.path, value);
  }
  return paths;
}

export function inspectJavaScriptSources(root: string) {
  const tracked = entries(root);
  const interpreters = executableJavaScript(root, tracked);
  const exceptions = readExemptions(root, tracked);
  const retained: Exception[] = [], unresolved: Entry[] = [], problems: string[] = [];
  for (const entry of tracked.values()) {
    if (!javascriptExtension.test(entry.path) && !interpreters.has(entry.path)) continue;
    const exception = exceptions.get(entry.path);
    if (exception) {
      if (exception.object === entry.object && exception.mode === entry.mode) retained.push(exception);
      else problems.push(`Changed bytes or mode for retained JavaScript: ${entry.path}`);
      exceptions.delete(entry.path);
      continue;
    }
    unresolved.push(entry);
    if (!regular(entry.mode)) problems.push(`Unclassified JavaScript source: ${entry.path}`);
  }
  for (const path of exceptions.keys()) problems.push(`Retired or non-JavaScript exception: ${path}`);
  return {complete: unresolved.length === 0 && problems.length === 0, retained, unresolved, problems};
}

function main(args: string[]) {
  const [mode] = args;
  assert(args.length <= 1 && (mode === undefined || mode === '--inventory'),
    'Usage: javascript-source-inventory.mjs [--inventory]');
  const root = fileURLToPath(new URL('../', import.meta.url));
  const result = inspectJavaScriptSources(root);
  if (mode === '--inventory') console.log(JSON.stringify(result, null, 2));
  else {
    console.log(`${result.retained.length} reviewed JavaScript files, ${result.unresolved.length} unclassified`);
    for (const {path} of result.unresolved.slice(0, 20)) console.error(`Unclassified JavaScript source: ${path}`);
    if (result.unresolved.length > 20) console.error('See npm run check:javascript-sources -- --inventory for the full list.');
  }
  for (const problem of result.problems) console.error(problem);
  if (result.problems.length || (mode === undefined && !result.complete)) process.exitCode = 1;
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) main(process.argv.slice(2));
