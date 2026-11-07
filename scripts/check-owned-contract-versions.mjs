import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstatSync, readFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const inventoryPath = 'scripts/owned-contract-version-legacy.json';
const baseline = '0.1';
const decoder = new TextDecoder('utf-8', {fatal: true});
// Namespace-qualified contracts, law IDs and schema URNs. Package versions,
// external protocols, Git SHAs and unqualified numeric data are not contracts.
const number = String.raw`[0-9]+(?:\.[0-9]+)*(?:[-+][A-Za-z0-9.-]+)?`;
const tokens = new RegExp([
  String.raw`\b(?:actql|aoa)[A-Za-z0-9_.-]*\/v?(${number})`,
  String.raw`\b(?:actql|aoa)\.[A-Za-z0-9_.-]+\.v(${number})`,
  String.raw`\burn:(?:actql|aoa):[A-Za-z0-9_.:-]+:(${number})`,
].join('|'), 'g');

function registryPackageVersionEnd(text, start) {
  if (start < 0 || (start > 0 && !/[\s"'`<>()]/u.test(text[start - 1]))) return -1;
  const raw = /^[^\s"'`<>()]+/u.exec(text.slice(start))?.[0];
  if (!raw) return -1;
  let url;
  try {url = new URL(raw);} catch {return -1;}
  if (url.href !== raw || url.username || url.password || url.search || url.hash) return -1;
  // Only a literal public package/version route is external version data.
  // Other URLs and adjacent owned identifiers still pass through the gate.
  const external = url.origin === 'https://registry.npmjs.org'
    ? /^\/(?:@[A-Za-z0-9_.-]+\/)?(?:actql|aoa)[A-Za-z0-9_.-]*\/[^/]+\/?$/u.test(url.pathname)
    : url.origin === 'https://pypi.org' &&
      (/^\/pypi\/(?:actql|aoa)[A-Za-z0-9_.-]*\/[^/]+\/json$/u.test(url.pathname) ||
        /^\/project\/(?:actql|aoa)[A-Za-z0-9_.-]*\/[^/]+\/?$/u.test(url.pathname));
  return external ? start + raw.length : -1;
}

export function occurrences(text, path) {
  const result = [];
  // Offsets increase within this one immutable text. Retain parser positions,
  // never a source admission or verdict between inputs. Look ahead lazily so
  // baseline-only files do not need another scan.
  let line = 1, nextNewline, nextUrl, urlStart = -1, registryEnd = -1;
  for (const match of text.matchAll(tokens)) {
    const version = match[1] ?? match[2] ?? match[3];
    if (version === baseline) continue;
    if (match[1]) {
      if (nextUrl === undefined) nextUrl = text.indexOf('https://');
      while (nextUrl >= 0 && nextUrl <= match.index) {
        urlStart = nextUrl;
        nextUrl = text.indexOf('https://', urlStart + 1);
        registryEnd = undefined;
      }
      if (registryEnd === undefined) registryEnd = registryPackageVersionEnd(text, urlStart);
      if (match.index < registryEnd) continue;
    }
    if (nextNewline === undefined) nextNewline = text.indexOf('\n');
    while (nextNewline >= 0 && nextNewline < match.index) {
      line++;
      nextNewline = text.indexOf('\n', nextNewline + 1);
    }
    // Freeze local source context, not merely a token or file-wide count:
    // a historical rejection fixture cannot authorize a new product writer.
    const context = text.slice(Math.max(0, match.index - 80),
      match.index + match[0].length + 80);
    const contextSha256 = createHash('sha256').update(context).digest('hex');
    result.push({path, token: match[0], contextSha256,
      line});
  }
  return result;
}

export function repositoryOccurrences(directory = root) {
  // Scan tracked files and new nonignored files before git add as well.
  const paths = [...new Set(execFileSync('git', ['ls-files', '-z',
    '--cached', '--others', '--exclude-standard'], {cwd: directory,
    encoding: 'utf8', maxBuffer: 16 * 1024 * 1024}).split('\0').filter(Boolean))].sort();
  return paths.flatMap(path => {
    if (path === inventoryPath) return [];
    let bytes;
    try {
      if (!lstatSync(join(directory, path)).isFile()) return [];
      bytes = readFileSync(join(directory, path));
    } catch (error) {
      if (error.code === 'ENOENT') return []; // A tracked deletion.
      throw error;
    }
    if (bytes.includes(0)) return [];
    let text;
    try { text = decoder.decode(bytes); } catch { return []; }
    return occurrences(text, path);
  });
}

const key = item => JSON.stringify([item.path, item.token, item.contextSha256]);

export function violations(found, inventory) {
  if (inventory.version !== 1 || inventory.baseline !== baseline ||
      !Array.isArray(inventory.entries)) throw new Error('InvalidVersionInventory');
  const remaining = new Map();
  for (const entry of inventory.entries) {
    if (typeof entry.path !== 'string' || typeof entry.token !== 'string' ||
        !/^[0-9a-f]{64}$/.test(entry.contextSha256) ||
        !Number.isSafeInteger(entry.count) || entry.count < 1 ||
        typeof entry.reason !== 'string' || !entry.reason ||
        remaining.has(key(entry))) throw new Error('InvalidVersionInventoryEntry');
    remaining.set(key(entry), entry.count);
  }
  return found.filter(item => {
    const count = remaining.get(key(item)) ?? 0;
    if (count === 0) return true;
    remaining.set(key(item), count - 1);
    return false;
  });
}

export function checkRepository(directory = root) {
  const inventory = JSON.parse(readFileSync(join(directory, inventoryPath), 'utf8'));
  const rejected = violations(repositoryOccurrences(directory), inventory);
  if (rejected.length) {
    throw new Error('Owned contracts must remain at 0.1. Do not bump a version ' +
      'or extend the legacy inventory without an explicit reviewed decision.\n' +
      rejected.map(item => `${item.path}:${item.line}: ${item.token}`).join('\n'));
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  checkRepository();
  console.log('Owned contract versions: 0.1; no new legacy-version occurrences.');
}
