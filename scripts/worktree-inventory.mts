// Opt-in metadata inventory. No deletion decisions, content reads or network I/O.
import {spawnSync} from 'node:child_process';
import type {SpawnSyncOptionsWithStringEncoding} from 'node:child_process';
import {lstatSync, opendirSync, realpathSync} from 'node:fs';
import type {Dir, Stats} from 'node:fs';
import {basename, isAbsolute, join, relative, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';

type Limits = {depth: number; entries: number; dependencyDepth: number; timeoutMs: number; commandBytes: number};
type CommandText = string | Buffer | null | undefined;
type CommandResult = {status: number | null; error?: NodeJS.ErrnoException; signal?: NodeJS.Signals | null;
  stdout?: CommandText; stderr?: CommandText};
type RunCommand = (program: string, args: string[], options: SpawnSyncOptionsWithStringEncoding) => CommandResult;
type InventoryOptions = {limits?: Partial<Limits>; run?: RunCommand; now?: () => Date; platform?: string;
  io?: {lstatSync(path: string): Stats; opendirSync(path: string): Dir; realpathSync(path: string): string}};
type ReportFailure = (check: string, path: string | null, reason: string) => void;
type GitInventory = {status: 'unknown' | 'observed'; changes: {path: string; status: string}[];
  trackedPaths: string[]; exclusions?: string[]};
type ObservedRoot = {requested: string; path: string; git: GitInventory};
type UnavailableRoot = {requested: string; path: null; status: 'unknown'; git?: never};
type LiveReference = {path: string; pid: string; descriptor: string; deleted: boolean};
type ProcessInventory = {status: 'unknown'; scope: string; snapshot?: 'observed' | 'incomplete';
  references: LiveReference[]};
type Candidate = {path: string; root: string; kind: 'dependencies' | 'regenerable-output';
  size: {allocatedBytes: number; status: 'observed' | 'partial'};
  protectedContents: {path: string; kind: string}[]; gitStatus: GitInventory['status'];
  references: {path: string; root: string; realPath: string | null; borrowed: boolean}[];
  usage: 'active' | 'unknown'; liveReferences?: LiveReference[]; review?: 'unknown' | 'referenced-by-symlink'};
type InventoryReport = {
  version: number; timestamp: string; requestedRoots: string[]; roots: (ObservedRoot | UnavailableRoot)[];
  limits: Limits; scope: string; warning: string; candidates: Candidate[]; protectedOutputs: Candidate[];
  processVisibility: {status: ProcessInventory['status']; scope: string;
    snapshot: NonNullable<ProcessInventory['snapshot']> | 'unavailable'};
  liveReferences: LiveReference[];
  protectedPaths: {path: string; root: string; kind: string}[];
  dependencyLinks: {path: string; root: string; realPath: string | null;
    status: 'unknown' | 'resolved'; insideDeclaredScope: boolean | null}[];
  exclusions: {path: string; reason: string}[];
  failedChecks: {check: string; path: string | null; reason: string}[];
  scannedEntries: number;
};
type FinalReportFields = 'processVisibility' | 'protectedOutputs' | 'scannedEntries';

const OUTPUT_NAMES = new Set(['_build', 'dist', 'target', '.next', '.cache',
  'coverage', '__pycache__', 'node_modules']);
const SOURCE_NAMES = new Set(['src', 'scripts', 'docs', 'spec', 'proofs',
  'vendor', '.github', 'test', 'tests']);
export const DEFAULT_LIMITS = Object.freeze({depth: 6, entries: 20000,
  dependencyDepth: 2, timeoutMs: 10000, commandBytes: 4 * 1024 * 1024});
const within = (parent: string, child: string) => {
  const tail = relative(parent, child);
  return tail === '' || (!tail.startsWith(`..${sep}`) && tail !== '..' &&
    !isAbsolute(tail));
};
const overlaps = (a: string, b: string) => within(a, b) || within(b, a);
const asText = (value: CommandText) => Buffer.isBuffer(value) ? value.toString('utf8') : value ?? '';

function protectedKind(path: string, root: string) {
  const parts = relative(root, path).split(sep);
  const name = basename(path).toLowerCase();
  if (parts.includes('.git')) return 'git-metadata';
  if (/^\.env(?:\.|$)|^\.npmrc$|^\.netrc$|^credentials?(?:\.|$)|^secrets?(?:\.|$)|^id_(rsa|ed25519|ecdsa)(?:\.|$)|\.(pem|key|p12|pfx)$/u.test(name) ||
      ['.ssh', '.aws', '.gnupg'].includes(name)) return 'credentials';
  if (/\.(db|sqlite|sqlite3|duckdb)(?:-(wal|shm|journal))?$|-(wal|shm)$/u.test(name)) return 'database';
  // These compiler/source modules are source, not runtime journals.
  if (SOURCE_NAMES.has(parts[0]) || (parts.includes('src') &&
      !parts.some(part => OUTPUT_NAMES.has(part)))) return 'source';
  if (['evidence', '.artifacts', 'artifacts', 'receipts'].includes(name)) return 'evidence';
  if (['journal', 'journals'].includes(name) || /\.journal$/u.test(name)) return 'runtime-journal';
  if (['.actql', 'recovery', 'checkpoints', 'checkpoint', 'recovery-records'].includes(name)) return 'recovery';
  return null;
}

function command(run: RunCommand, program: string, args: string[], limits: Limits, cwd?: string): CommandResult {
  try {
    return run(program, args, {cwd, encoding: 'utf8', timeout: limits.timeoutMs,
      maxBuffer: limits.commandBytes, windowsHide: true,
      env: {...process.env, GIT_OPTIONAL_LOCKS: '0', GIT_TERMINAL_PROMPT: '0'}});
  } catch (error) {
    return {status: null, error: error as NodeJS.ErrnoException};
  }
}

function commandProblem(result: CommandResult) {
  return result.error?.code ?? (result.signal ? `signal:${result.signal}` :
    `exit:${result.status ?? 'unknown'}`);
}

function gitInventory(root: string, run: RunCommand, limits: Limits, fail: ReportFailure) {
  const execute = (args: string[]) => command(run, 'git', ['--no-optional-locks', '-C',
    root, '-c', 'core.fsmonitor=false', '-c', 'core.untrackedCache=false',
    ...args], limits);
  const result: GitInventory = {status: 'unknown', changes: [], trackedPaths: []};
  const top = execute(['rev-parse', '--show-toplevel']);
  if (top.status !== 0 || top.error) {
    fail('git-root', root, commandProblem(top));
    return result;
  }
  // rev-parse has no NUL variant: remove only its final line ending.
  const topPath = asText(top.stdout).replace(/\r?\n$/u, '');
  if (resolve(topPath) !== root) {
    fail('git-root', root, 'explicit root is not the worktree top level');
    return result;
  }
  const tracked = execute(['ls-files', '--cached', '-z']);
  const status = execute(['status', '--porcelain=v1', '-z', '--no-renames',
    '--untracked-files=all', '--ignore-submodules=all']);
  if (tracked.status !== 0 || tracked.error) fail('git-tracked', root, commandProblem(tracked));
  else result.trackedPaths = asText(tracked.stdout).split('\0').filter(Boolean);
  if (status.status !== 0 || status.error) fail('git-status', root, commandProblem(status));
  else result.changes = asText(status.stdout).split('\0').filter(Boolean)
    .map(record => ({status: record.slice(0, 2), path: record.slice(3)}));
  if (result.trackedPaths.length > limits.entries || result.changes.length > limits.entries) {
    result.trackedPaths = result.trackedPaths.slice(0, limits.entries);
    result.changes = result.changes.slice(0, limits.entries);
    fail('git-inventory', root, 'entry limit; Git protection inventory incomplete');
  } else if (tracked.status === 0 && !tracked.error && status.status === 0 && !status.error) {
    result.status = 'observed';
  }
  result.exclusions = ['submodule working directory status (scan it as an explicit root)'];
  return result;
}

// lsof's field mode preserves spaces and separates records with NULs.
export function parseLsof(output: CommandText): LiveReference[] {
  let pid: string | undefined;
  let descriptor: string | undefined;
  const references = [];
  for (const raw of asText(output).split('\0')) {
    const field = raw.replace(/^\n/u, '');
    const tag = field[0];
    const value = field.slice(1);
    if (tag === 'p') { pid = value; descriptor = undefined; }
    else if (tag === 'f') descriptor = value;
    else if (tag === 'n' && pid && descriptor && isAbsolute(value)) {
      const deleted = value.endsWith(' (deleted)');
      references.push({pid, descriptor, path: deleted ? value.slice(0, -10) : value,
        deleted});
    }
  }
  return references;
}

function processInventory(run: RunCommand, limits: Limits, platform: string, fail: ReportFailure): ProcessInventory {
  const scope = 'Visible lsof snapshot only; other users, namespaces, races and unopened paths are not proven absent';
  if (!['linux', 'darwin'].includes(platform)) {
    fail('process-visibility', null, `unsupported platform: ${platform}`);
    return {status: 'unknown', scope, references: []};
  }
  // Some lsof dialects otherwise create/update a personal device cache.
  // Help is metadata-only and advertises -D exactly when that facility exists.
  const help = command(run, 'lsof', ['-h'], limits);
  const helpText = asText(help.stdout) + asText(help.stderr);
  if (help.error || !helpText.includes('lsof') || !helpText.includes('-F')) {
    fail('process-visibility', null, help.error ? commandProblem(help) : 'cannot determine read-only lsof options');
    return {status: 'unknown', scope, references: []};
  }
  const flags = ['-nP', '-l', '-M', '-F0pfn'];
  if (helpText.includes('-D')) flags.unshift('-Di');
  const result = command(run, 'lsof', flags, limits);
  const references = parseLsof(result.stdout);
  if (result.status !== 0 || result.error || asText(result.stderr).trim()) {
    fail('process-visibility', null, result.error || result.status !== 0 ?
      commandProblem(result) : 'lsof reported warnings; visibility incomplete');
  }
  return {status: 'unknown', scope, references,
    snapshot: result.status === 0 && !result.error && !asText(result.stderr).trim() ?
      'observed' : 'incomplete'};
}

export function inventoryWorktrees(roots: readonly string[], options: InventoryOptions = {}): InventoryReport {
  if (!Array.isArray(roots) || roots.length === 0 || roots.length > 32 ||
      roots.some(root => typeof root !== 'string' || root.length === 0)) {
    throw new Error('Provide between 1 and 32 explicit worktree roots');
  }
  const limits = {...DEFAULT_LIMITS, ...options.limits};
  for (const key of Object.keys(DEFAULT_LIMITS) as (keyof Limits)[]) {
    if (!Number.isSafeInteger(limits[key]) || limits[key] < 1) throw new Error(`Invalid ${key} limit`);
  }
  if (limits.depth > 64 || limits.dependencyDepth > 64 || limits.entries > 1000000) {
    throw new Error('Limits exceed maximum depth 64 or entries 1000000');
  }
  const io = options.io ?? {lstatSync, opendirSync, realpathSync};
  const run = options.run ?? spawnSync;
  const report: Omit<InventoryReport, FinalReportFields> & Partial<Pick<InventoryReport, FinalReportFields>> = {version: 1, timestamp: (options.now ?? (() => new Date()))().toISOString(),
    requestedRoots: roots.map(root => resolve(root)), roots: [], limits,
    scope: 'Explicit roots only. Symlink targets are resolved, never traversed through the link. Reverse references cover observed links in these roots only.',
    warning: 'Evidence for review only; no path is certified unused or authorized for deletion. Sizes are allocated blocks, not guaranteed reclaimable space.',
    candidates: [], protectedPaths: [], dependencyLinks: [], liveReferences: [],
    exclusions: [], failedChecks: []};
  const fail: ReportFailure = (check, path, reason) => report.failedChecks.push({check, path, reason});
  const exclude = (path: string, reason: string) => report.exclusions.push({path, reason});
  const protect = (path: string, root: string, kind: string) => report.protectedPaths.push({path, root, kind});
  let visited = 0;
  let exhausted = false;
  const sizeSeen = new Map<Candidate, Set<string>>();
  const gitProtection = new Map<string, {tracked: Set<string>; trackedExact: Set<string>; changed: Set<string>}>();
  function ancestors(root: string, paths: readonly string[]) {
    const result = new Set<string>();
    for (const path of paths) {
      let current = join(root, path);
      while (within(root, current)) {
        result.add(current);
        if (current === root) break;
        current = resolve(current, '..');
      }
    }
    return result;
  }

  function entries(path: string) {
    const result = [];
    let handle: Dir | undefined;
    try {
      handle = io.opendirSync(path);
      while (true) {
        if (visited >= limits.entries) {
          if (!exhausted) exclude(path, 'global entry limit reached; remaining directories not scanned');
          exhausted = true;
          return {entries: result, complete: false};
        }
        const entry = handle.readSync();
        if (!entry) break;
        visited += 1;
        result.push(entry.name);
      }
      return {entries: result.sort(), complete: true};
    } catch (error) {
      fail('directory', path, (error as NodeJS.ErrnoException).code ?? 'read failed');
      return {entries: result, complete: false};
    } finally {
      try { handle?.closeSync(); }
      catch (error) { fail('directory-close', path, (error as NodeJS.ErrnoException).code ?? 'close failed'); }
    }
  }

  function stat(path: string) {
    try { return io.lstatSync(path); }
    catch (error) { fail('metadata', path, (error as NodeJS.ErrnoException).code ?? 'stat failed'); return null; }
  }

  function link(path: string, root: string) {
    let realPath: string | null = null;
    let status: 'unknown' | 'resolved' = 'unknown';
    try {
      realPath = io.realpathSync(path);
      status = 'resolved';
    } catch (error) {
      fail('symlink', path, (error as NodeJS.ErrnoException).code ?? 'resolution failed');
    }
    // realpath resolves nested component links; the OS rejects loops with ELOOP.
    report.dependencyLinks.push({path, root, realPath, status,
      insideDeclaredScope: realPath === null ? null :
        report.roots.some(item => item.path && within(item.path, realPath!))});
    exclude(path, 'symlink target not traversed or included in allocated size');
  }

  function protection(path: string, root: ObservedRoot) {
    const kind = protectedKind(path, root.path);
    const tracked = gitProtection.get(root.path)!.tracked.has(path);
    // A tracked compiler module is not runtime journal data just because of
    // its name. Credentials and database-looking files remain protected.
    if (kind && kind !== 'source' && !(kind === 'runtime-journal' && tracked)) return kind;
    if (gitProtection.get(root.path)!.changed.has(path)) return 'dirty-or-untracked';
    if (tracked) return 'tracked-source';
    return kind;
  }

  // Count each inode only once within a candidate. Hardlinks across candidates
  // or reflinks still do not imply that this many bytes can be reclaimed.
  function addSize(path: string, metadata: Stats, candidate: Candidate | null) {
    if (!candidate) return;
    const seen = sizeSeen.get(candidate)!;
    const key = `${metadata.dev}:${metadata.ino}`;
    if (seen.has(key)) return;
    seen.add(key);
    if (typeof metadata.blocks !== 'number' || !Number.isSafeInteger(metadata.blocks * 512)) {
      candidate.size.status = 'partial';
      fail('allocated-size', path, 'allocated block count unavailable');
    } else candidate.size.allocatedBytes += metadata.blocks * 512;
  }

  function walk(path: string, root: ObservedRoot, depth: number, candidate: Candidate | null = null,
    dependencyLevel: number | null = null) {
    if (exhausted) { if (candidate) candidate.size.status = 'partial'; return; }
    const metadata = stat(path);
    if (!metadata) { if (candidate) candidate.size.status = 'partial'; return; }
    const kind = protection(path, root);
    const name = basename(path);
    const hardProtection = kind && kind !== 'source' && kind !== 'tracked-source' && kind !== 'dirty-or-untracked';
    if (hardProtection) {
      protect(path, root.path, kind);
      if (candidate) { candidate.protectedContents.push({path, kind}); candidate.size.status = 'partial'; }
      exclude(path, `${kind}: metadata only, contents not traversed`);
      return;
    }
    if (metadata.isDirectory() && gitProtection.get(root.path)!.trackedExact.has(path)) {
      protect(path, root.path, kind ?? 'tracked-source');
      exclude(path, 'tracked directory/gitlink: scan its worktree as an explicit root');
      if (candidate) { candidate.protectedContents.push({path, kind: 'tracked-source'}); candidate.size.status = 'partial'; }
      return;
    }
    if (metadata.isSymbolicLink()) {
      link(path, root.path);
      protect(path, root.path, kind ?? 'symbolic-link');
      addSize(path, metadata, candidate);
      return;
    }
    const output = metadata.isDirectory() && OUTPUT_NAMES.has(name);
    if (!candidate && output && !kind) {
      candidate = {path, root: root.path, kind: name === 'node_modules' ? 'dependencies' : 'regenerable-output',
        size: {allocatedBytes: 0, status: 'observed'}, protectedContents: [],
        gitStatus: root.git.status, references: [], usage: 'unknown'};
      sizeSeen.set(candidate, new Set());
      report.candidates.push(candidate);
    } else if (kind || !candidate) {
      protect(path, root.path, kind ?? 'unclassified-source-or-data');
      if (candidate && kind) candidate.protectedContents.push({path, kind});
    }
    addSize(path, metadata, candidate);
    if (!metadata.isDirectory()) return;
    if (name === 'node_modules' && dependencyLevel === null) dependencyLevel = 0;
    if (depth >= limits.depth || (dependencyLevel !== null && dependencyLevel >= limits.dependencyDepth)) {
      exclude(path, dependencyLevel !== null && dependencyLevel >= limits.dependencyDepth ?
        'dependency depth limit; package contents not recursively traversed by default' : 'scan depth limit');
      if (candidate) candidate.size.status = 'partial';
      return;
    }
    const children = entries(path);
    if (candidate && !children.complete) candidate.size.status = 'partial';
    for (const name of children.entries) {
      walk(join(path, name), root, depth + 1, candidate,
        dependencyLevel === null ? null : dependencyLevel + 1);
    }
  }

  for (const requested of report.requestedRoots) {
    try {
      const path = io.realpathSync(requested);
      if (!io.lstatSync(path).isDirectory()) throw Object.assign(new Error(), {code: 'ENOTDIR'});
      if (report.roots.some(item => item.path === path)) { exclude(requested, 'duplicate resolved root'); continue; }
      const git = gitInventory(path, run, limits, fail);
      report.roots.push({requested, path, git});
      gitProtection.set(path, {tracked: ancestors(path, git.trackedPaths),
        trackedExact: new Set(git.trackedPaths.map(item => join(path, item))),
        changed: ancestors(path, git.changes.map(item => item.path))});
    } catch (error) { report.roots.push({requested, path: null, status: 'unknown'}); fail('root', requested, (error as NodeJS.ErrnoException).code ?? 'unavailable'); }
  }
  for (const root of report.roots.filter(item => item.path)) {
    if (exhausted) { exclude(root.path!, 'global entry limit; root not scanned'); continue; }
    const children = entries(root.path!);
    for (const name of children.entries) walk(join(root.path!, name), root as ObservedRoot, 1);
  }
  const processes = processInventory(run, limits, options.platform ?? process.platform, fail);
  report.processVisibility = {status: processes.status, scope: processes.scope,
    snapshot: processes.snapshot ?? 'unavailable'};
  report.liveReferences = processes.references.filter(reference =>
    report.roots.some(root => root.path && within(root.path, reference.path)));
  for (const candidate of report.candidates) {
    candidate.references = report.dependencyLinks.filter(item => item.realPath &&
      overlaps(candidate.path, item.realPath)).map(item => ({path: item.path,
      root: item.root, realPath: item.realPath, borrowed: item.root !== candidate.root}));
    candidate.liveReferences = report.liveReferences.filter(item => within(candidate.path, item.path));
    candidate.usage = candidate.liveReferences.length ? 'active' : 'unknown';
    candidate.review = candidate.references.length ? 'referenced-by-symlink' : 'unknown';
  }
  // A generated-looking parent containing protected data is not a reclaim candidate.
  const protectedCandidates = report.candidates.filter(candidate => candidate.protectedContents.length);
  for (const candidate of protectedCandidates) protect(candidate.path, candidate.root, 'contains-protected-paths');
  report.protectedOutputs = protectedCandidates;
  report.candidates = report.candidates.filter(candidate => candidate.protectedContents.length === 0)
    .sort((a, b) => b.size.allocatedBytes - a.size.allocatedBytes || a.path.localeCompare(b.path));
  report.scannedEntries = visited;
  return report as InventoryReport;
}

export function formatInventory(report: InventoryReport) {
  const lines = [`Worktree inventory ${report.timestamp}`, report.warning,
    `Scope: ${report.scope}`, `Limits: ${JSON.stringify(report.limits)}`,
    `Process visibility: ${report.processVisibility.status} (${report.processVisibility.snapshot})`,
    report.processVisibility.scope, 'Roots:'];
  for (const root of report.roots) {
    lines.push(`  ${JSON.stringify(root.requested)} => ${JSON.stringify(root.path)}; Git ${root.git?.status ?? 'unknown'}`);
    for (const change of root.git?.changes ?? []) lines.push(`    ${change.status} ${JSON.stringify(change.path)}`);
    for (const exclusion of root.git?.exclusions ?? []) lines.push(`    Excluded: ${exclusion}`);
  }
  lines.push('Largest regenerable-output candidates (review required):');
  for (const item of report.candidates) {
    lines.push(`  ${item.size.allocatedBytes} allocated bytes (${item.size.status}${item.size.status === 'partial' ? ', lower bound' : ''}) ${JSON.stringify(item.path)}; usage ${item.usage}; Git ${item.gitStatus}`);
    for (const reference of item.references) lines.push(`    ${reference.borrowed ? 'Borrowed' : 'Link'}: ${JSON.stringify(reference.path)} => ${JSON.stringify(reference.realPath)}`);
  }
  lines.push('Protected paths (never cleanup candidates):');
  for (const item of report.protectedPaths) lines.push(`  ${item.kind}: ${JSON.stringify(item.path)}`);
  lines.push('Dependency/symbolic links (declared scan scope only):');
  for (const item of report.dependencyLinks) lines.push(`  ${JSON.stringify(item.path)} => ${JSON.stringify(item.realPath)} (${item.status})`);
  lines.push('Live file/cwd references observed:');
  for (const item of report.liveReferences) lines.push(`  pid ${item.pid} ${item.descriptor}: ${JSON.stringify(item.path)}`);
  lines.push('Exclusions:');
  for (const item of report.exclusions) lines.push(`  ${JSON.stringify(item.path)}: ${item.reason}`);
  lines.push('Failed checks (unknown, never unused):');
  for (const item of report.failedChecks) lines.push(`  ${item.check} ${JSON.stringify(item.path)}: ${item.reason}`);
  return `${lines.join('\n')}\n`;
}

export function parseArgs(args: readonly string[]) {
  const roots = [];
  const options: {limits: Partial<Limits>} = {limits: {}};
  let json = false;
  const numbers = new Map<string, keyof Limits>([['--max-depth', 'depth'], ['--max-entries', 'entries'],
    ['--dependency-depth', 'dependencyDepth'], ['--timeout-ms', 'timeoutMs']]);
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--') { roots.push(...args.slice(index + 1)); break; }
    if (arg === '--json') json = true;
    else if (numbers.has(arg)) {
      const value = args[++index];
      if (!/^\d+$/u.test(value ?? '')) throw new Error(`${arg} requires a positive integer`);
      options.limits[numbers.get(arg)!] = Number(value);
    } else if (arg.startsWith('-')) throw new Error(`Unknown option: ${arg}`);
    else roots.push(arg);
  }
  return {roots, options, json};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const {roots, options, json} = parseArgs(process.argv.slice(2));
    const report = inventoryWorktrees(roots, options);
    process.stdout.write(json ? `${JSON.stringify(report, null, 2)}\n` : formatInventory(report));
  } catch (error) {
    console.error(`${(error as Error).message}\nUsage: node scripts/worktree-inventory.mjs [--json] [--max-depth N] [--max-entries N] [--dependency-depth N] [--timeout-ms N] -- ROOT [ROOT ...]`);
    process.exitCode = 2;
  }
}
