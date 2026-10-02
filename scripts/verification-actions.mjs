// Read-only declaration inventory. Never execute commands or infer dependency closure.
import {openSync, readSync, fstatSync, closeSync, constants} from 'node:fs';
import {resolve, join, relative} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {parseDocument, LineCounter} from 'yaml';

const usage = 'Usage: node scripts/verification-actions.mjs [--root DIR] ' +
  '[--workflow PATH] [--json]';
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const canonical = value => JSON.stringify(value, (_key, item) => object(item)
  ? Object.fromEntries(Object.keys(item).sort().map(key => [key, item[key]])) : item);
const same = (a, b) => canonical(a) === canonical(b);
const unknownDependencies = [
  'Transitive inputs and generated files are not enumerated',
  'Resolved compiler/runtime bytes and inherited environment are not observed',
  'Earlier commands, actions, mutations and external services can change execution state',
  'Separate executions are independent observations, including failure-injection and restoration',
];

// Deliberately small shell grammar: literal words, quotes, whitespace, && and
// newlines. Never expand variables, globs, substitutions, pipelines or loops.
// Refuse the whole block, not a potentially unconditional fragment of a loop.
export function parseCommands(source) {
  if (typeof source !== 'string') return {commands: [], reason: 'Non-string command'};
  const commands = [];
  let words = [], word = '', started = false, quote = null, operator = 'start', line = 1, start = 1;
  const pushWord = () => { if (started) words.push(word); word = ''; started = false; };
  const pushCommand = next => {
    pushWord();
    if (words.length) commands.push({argv: words, after: operator, line: start});
    else if (next === '&&') throw new Error('Empty && operand');
    else if (operator === '&&') return;
    words = []; operator = next; start = line;
  };
  try {
    for (let i = 0; i < source.length; i++) {
      const c = source[i];
      if (c === '\r' || c === '\0') throw new Error('Unsupported control character');
      if (c === '\\') {
        if (source[i + 1] === '\n' && quote !== "'") { i++; line++; continue; }
        throw new Error('Unsupported shell escape');
      }
      if (quote) {
        if (c === quote) quote = null;
        else {
          if (quote === '"' && /[$`]/u.test(c)) throw new Error('Dynamic quoted shell expression');
          word += c;
          if (c === '\n') line++;
        }
        continue;
      }
      if (c === "'" || c === '"') { quote = c; started = true; continue; }
      if (c === '#' && !started) {
        while (i < source.length && source[i] !== '\n') i++;
        if (i < source.length) { line++; pushCommand('newline'); start = line; }
        continue;
      }
      if (c === '&' && source[i + 1] === '&') { pushCommand('&&'); i++; continue; }
      if (/[|;&<>$`(){}*?\[\]~!]/u.test(c)) throw new Error('Dynamic or unsupported shell syntax');
      if (c === '\n') { line++; pushCommand('newline'); start = line; continue; }
      if (/\s/u.test(c)) { pushWord(); continue; }
      if (!started && words.length === 0) start = line;
      word += c; started = true;
    }
    if (quote) throw new Error('Unclosed shell quote');
    pushWord();
    if (!words.length && operator === '&&') throw new Error('Trailing &&');
    if (words.length) commands.push({argv: words, after: operator, line: start});
    const reserved = new Set(['if', 'then', 'else', 'fi', 'for', 'while', 'until', 'do', 'done',
      'case', 'esac', 'function', 'select', 'export', 'cd', 'source', '.', 'eval', 'exec', 'set']);
    for (const command of commands) {
      if (reserved.has(command.argv[0])) throw new Error('Unsupported stateful shell command');
    }
    return {commands, reason: null};
  } catch (error) { return {commands: [], reason: error.message}; }
}

function invocation(argv) {
  const env = {};
  while (/^[A-Za-z_][A-Za-z_0-9]*=/u.test(argv[0] ?? '')) {
    const assignment = argv.shift(), equal = assignment.indexOf('=');
    env[assignment.slice(0, equal)] = assignment.slice(equal + 1);
  }
  const [executable, operation] = argv;
  let subject = null, kind = null;
  if (executable === 'node' && operation === '--test') {
    kind = 'node-test'; subject = argv.slice(2).find(value => !value.startsWith('-'));
  } else if (executable === 'node' && /\.(?:mjs|cjs|js)$/u.test(operation ?? '')) {
    kind = 'node-script'; subject = operation;
  } else if (executable === 'moon' && ['build', 'check', 'test', 'fmt'].includes(operation)) {
    kind = 'moon'; subject = operation;
  } else if (executable === 'npm' && operation === 'run' && argv.length === 3) {
    kind = 'npm-script'; subject = argv[2];
  }
  const targetIndex = argv.indexOf('--target');
  const targetEquals = argv.find(value => value.startsWith('--target='));
  const target = targetIndex >= 0 ? argv[targetIndex + 1] ?? null : targetEquals?.slice(9) ?? null;
  // Keep the complete argv as authority. These are selectors, never file identities.
  const selectors = argv.slice(kind === 'node-script' ? 1 : 2).filter(value =>
    !value.startsWith('-'));
  return {argv, env, kind, subject, target, selectors,
    flags: argv.filter(value => value.startsWith('-')),
    reason: kind ? null : 'Unrecognized invocation (not executed or expanded)'};
}

function sourceLocation(path, counter, node, suffix = '') {
  const at = counter.linePos(node?.range?.[0] ?? 0);
  return {path, line: at.line, column: at.col, ...(suffix ? {definition: suffix} : {})};
}

function parseYaml(text, path) {
  const counter = new LineCounter();
  const document = parseDocument(text, {lineCounter: counter, uniqueKeys: true});
  if (document.errors.length) throw new Error(`Invalid YAML: ${path}`);
  const value = document.toJS({maxAliasCount: 0});
  if (!object(value)) throw new Error(`Expected mapping: ${path}`);
  return {document, counter, value};
}

function matrixCases(job) {
  if (!job.strategy?.matrix) return [{values: {}, reason: null}];
  const matrix = job.strategy.matrix;
  if (!object(matrix) || Object.keys(matrix).some(key => ['include', 'exclude'].includes(key)) ||
      Object.values(matrix).some(values => !Array.isArray(values) || !values.length ||
        values.some(value => !['string', 'number', 'boolean'].includes(typeof value) ||
          !/^[-A-Za-z0-9_.:/]+$/u.test(String(value))))) {
    return [{values: {}, reason: 'Dynamic or unsupported matrix; no expansion claimed'}];
  }
  let cases = [{}];
  for (const [key, values] of Object.entries(matrix)) {
    if (cases.length * values.length > 64) return [{values: {}, reason: 'Matrix exceeds 64 cases'}];
    cases = cases.flatMap(item => values.map(value => ({...item, [key]: String(value)})));
  }
  return cases.map(values => ({values, reason: null}));
}

// Matrix replacement is limited to safe literal tokens even inside quotes.
// Remaining expressions become opaque in parseCommands.
const substitute = (text, values) => String(text).replace(/\$\{\{\s*matrix\.([A-Za-z_][\w-]*)\s*\}\}/gu,
  (match, key) => /^[A-Za-z0-9_.:/-]+$/u.test(values[key] ?? '') ? values[key] : match);

export function compareActions(left, right) {
  const result = {left: left.id, right: right.id, invocationEquality: 'unknown',
    equivalence: 'unknown', eligibleForReuse: false, differences: [], reasons: []};
  if (!left.invocation?.kind || !right.invocation?.kind || left.unresolved.length || right.unresolved.length) {
    result.reasons.push('Unrecognized or dynamic declaration prevents comparison');
    return result;
  }
  result.invocationEquality = same(left.invocation.argv, right.invocation.argv) ? 'proven' : 'different';
  for (const key of ['argv', 'target', 'selectors', 'flags']) {
    if (!same(left.invocation[key], right.invocation[key])) result.differences.push(key);
  }
  for (const key of ['environment', 'compiler', 'workingDirectory', 'shell', 'matrix']) {
    if (!same(left[key], right[key])) result.differences.push(key);
  }
  if (result.differences.length) {
    result.equivalence = 'different';
    result.reasons.push('Known declaration dimensions differ; not an equivalent-action candidate');
  } else if (!same(left.purpose, right.purpose) || !same(left.condition, right.condition) ||
      left.origin !== right.origin || !same(left.state.priorCommands, right.state.priorCommands)) {
    result.reasons.push('Matching invocation has a different declared purpose, condition, prior commands or local/CI entrypoint');
  } else {
    result.equivalence = 'suspected';
    result.reasons.push('Literal invocation and observed configuration match; candidate for investigation only');
  }
  result.reasons.push(...unknownDependencies);
  return result;
}

// Pure report builder: all sources are explicit strings; no filesystem, shell,
// imports of inspected code, network, environment collection or action key.
export function inventory({workflowText, packageText, localRunnerText = '',
  toolchainText = '', workflowPath = '.github/workflows/ci.yml'}) {
  const {document, counter, value: workflow} = parseYaml(workflowText, workflowPath);
  if (!object(workflow.jobs)) throw new Error('Workflow jobs must be a mapping');
  const manifest = JSON.parse(packageText);
  if (!object(manifest.scripts ?? {})) throw new Error('Package scripts must be a mapping');
  const scripts = manifest.scripts ?? {};
  const packageDocument = parseYaml(packageText, 'package.json');
  const actions = [], omissions = [];
  let sequence = 0;
  const packageSource = name => sourceLocation('package.json', packageDocument.counter,
    packageDocument.document.getIn(['scripts', name], true), `scripts.${name}`);
  const emit = (run, context, sources, stack = []) => {
    const trace = [];
    const history = [...context.state.priorCommands];
    const currentContext = () => ({...context, state: {...context.state, priorCommands: [...history]}});
    const record = action => {
      if (actions.length >= 5000) throw new Error('Action inventory exceeds 5000 occurrences');
      actions.push(action);
      const event = {occurrence: action.id};
      history.push(event); trace.push(event);
    };
    const parsed = parseCommands(run);
    if (parsed.reason) {
      record({...currentContext(), id: `action-${++sequence}`, source: sources,
        invocation: null, unresolved: [...context.unresolved, parsed.reason],
        declaration: run, inputIdentity: 'unavailable', faultState: 'unknown'});
      return trace;
    }
    for (const command of parsed.commands) {
      const current = invocation([...command.argv]);
      const environment = {...context.environment, ...current.env};
      const source = sources.map((item, index) => index === sources.length - 1
        ? {...item, commandLineOffset: command.line - 1} : item);
      if (current.kind === 'npm-script') {
        const name = current.subject;
        if (stack.includes(name) || stack.length >= 20 || typeof scripts[name] !== 'string') {
          record({...currentContext(), id: `action-${++sequence}`, source, invocation: current,
            environment, unresolved: [...context.unresolved, 'Missing, recursive or non-string npm script'],
            inputIdentity: 'unavailable', faultState: 'unknown'});
          continue;
        }
        // npm run executes pre/post hooks too. Carry every predecessor through
        // nested hooks and back to the caller; none is a pure/read-only action.
        for (const phase of [`pre${name}`, name, `post${name}`]) {
          if (Object.hasOwn(scripts, phase)) {
            if (typeof scripts[phase] !== 'string') throw new Error('Non-string npm lifecycle hook');
            const nested = emit(scripts[phase], {...currentContext(), environment,
              condition: {...context.condition, npmLifecycle: phase, after: command.after},
              unresolved: [...context.unresolved]}, [...source, packageSource(phase)], [...stack, name]);
            history.push(...nested); trace.push(...nested);
          }
        }
      } else {
        record({...currentContext(), id: `action-${++sequence}`, source, invocation: current, environment,
          condition: {...context.condition, after: command.after},
          unresolved: [...context.unresolved, ...(current.reason ? [current.reason] : [])],
          inputIdentity: 'unavailable', faultState: 'unknown'});
      }
    }
    return trace;
  };
  for (const [jobName, job] of Object.entries(workflow.jobs)) {
    if (!object(job)) throw new Error('Job must be a mapping');
    if (!Array.isArray(job.steps)) {
      omissions.push({source: sourceLocation(workflowPath, counter, document.getIn(['jobs', jobName], true)),
        job: jobName, reason: 'Reusable or unsupported job is opaque', uses: job.uses ?? null});
      continue;
    }
    for (const matrix of matrixCases(job)) {
      const setup = [], priorCommands = [];
      for (const [index, step] of job.steps.entries()) {
        if (!object(step)) throw new Error('Step must be a mapping');
        const node = document.getIn(['jobs', jobName, 'steps', index], true);
        const source = sourceLocation(workflowPath, counter, node, `jobs.${jobName}.steps[${index}]`);
        if (step.uses) {
          setup.push({uses: step.uses, with: step.with ?? {}, if: step.if ?? null});
          omissions.push({source, job: jobName, matrix: matrix.values,
            reason: 'Action implementation and state effects are opaque', uses: step.uses});
        }
        if (step.run === undefined) continue;
        const getDefault = key => step[key] ?? job.defaults?.run?.[key] ?? workflow.defaults?.run?.[key] ?? null;
        const shell = getDefault('shell');
        const unsupportedShell = shell !== null && !['bash', 'sh'].includes(shell);
        const env = {...workflow.env, ...job.env, ...step.env};
        const context = {origin: 'workflow', job: jobName, matrix: matrix.values, step: index,
          purpose: step.name ?? null, condition: {job: job.if ?? null, step: step.if ?? null,
            continueOnError: step['continue-on-error'] ?? false, needs: job.needs ?? []},
          workingDirectory: getDefault('working-directory') ?? '<checkout>', shell: shell ?? '<runner-default>',
          compiler: {requestedExecutable: null, runner: job['runs-on'] ?? null,
            setup: structuredClone(setup), pinDeclaration: toolchainText || null},
          environment: Object.fromEntries(Object.entries(env).map(([key, value]) => [key, substitute(value, matrix.values)])),
          state: {priorStepCount: index, priorEffects: 'unknown', inheritedEnvironment: 'unknown', priorCommands: [...priorCommands]},
          unresolved: [...(matrix.reason ? [matrix.reason] : []),
            ...(substitute(step.run, matrix.values).includes('${{') ? ['Unresolved workflow expression'] : []),
            ...(unsupportedShell ? ['Unsupported shell; literal command grammar is not applicable'] : []),
            ...(/\$[({]/u.test(canonical([env, getDefault('working-directory'), job['runs-on'], setup]))
              ? ['Dynamic environment, directory, runner or action configuration'] : [])]};
        emit(substitute(step.run, matrix.values), context, [source]);
        priorCommands.push({source, run: step.run});
      }
    }
  }
  // These are callable local definitions, not extra executions in a CI run.
  for (const [name, run] of Object.entries(scripts)) {
    if (!/^(?:check:|test(?::|$))/u.test(name)) continue;
    if (typeof run !== 'string') throw new Error('Non-string npm script');
    emit(`npm run '${name}'`, {origin: 'local-definition', job: `npm run ${name}`, matrix: {}, step: null,
      purpose: name, condition: {manual: true}, workingDirectory: '<package-root>', shell: '<npm-config>',
      compiler: {requestedExecutable: null, runner: '<developer-machine>', setup: [], pinDeclaration: toolchainText || null},
      environment: {}, state: {priorEffects: 'unknown', inheritedEnvironment: 'unknown', priorCommands: []}, unresolved: []}, [packageSource(name)]);
  }
  for (const action of actions) {
    action.compiler = {...action.compiler, requestedExecutable: action.invocation?.argv[0] ?? null};
  }
  const groups = new Map();
  for (const action of actions) {
    if (!action.invocation?.kind) continue;
    const anchor = canonical([action.invocation.kind, action.invocation.subject]);
    const group = groups.get(anchor) ?? [];
    group.push(action); groups.set(anchor, group);
  }
  const comparisons = [];
  for (const group of groups.values()) {
    for (let i = 0; i < group.length; i++) for (let j = i + 1; j < group.length; j++) {
      if (comparisons.length >= 20000) throw new Error('Comparison inventory exceeds 20000 pairs');
      comparisons.push(compareActions(group[i], group[j]));
    }
  }
  const runnerLines = localRunnerText.split('\n');
  return {schema: 'actql-verification-scheduling-report/0.1', reportOnly: true, eligibleForReuse: false,
    scope: 'Declared workflow occurrences and callable local package definitions; no executions observed',
    actionIdentity: {status: 'unavailable', reason: 'No complete action-input evidence is supplied',
      owner: 'proofs/bounded-session/action-inputs.mjs (#195 / #214)',
      integration: 'Use that module to compare two explicit bounded-session manifests after integration; equal observed inputs never permit reuse'},
    localRunner: {source: {path: 'scripts/local-checks.mjs'}, status: 'unknown',
      workflowReferenceLines: runnerLines.flatMap((line, i) => line.includes('.github/workflows/ci.yml') ? [i + 1] : []),
      reason: 'Inspected as text only. No JavaScript executed; local command filtering and substitutions are not certified'},
    boundaries: unknownDependencies, actions, comparisons, omissions,
    summary: {occurrences: actions.length, opaqueOccurrences: actions.filter(action => action.unresolved.length).length,
      comparisons: comparisons.length, suspected: comparisons.filter(item => item.equivalence === 'suspected').length,
      unknown: comparisons.filter(item => item.equivalence === 'unknown').length,
      different: comparisons.filter(item => item.equivalence === 'different').length}};
}

function readText(path) {
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const before = fstatSync(fd);
    if (!before.isFile() || before.size > 2 * 1024 * 1024) {
      throw new Error('Input must be a regular file of at most 2 MiB');
    }
    const bytes = Buffer.alloc(before.size + 1);
    let length = 0, count;
    while (length < bytes.length && (count = readSync(fd, bytes, length, bytes.length - length, null))) length += count;
    const after = fstatSync(fd);
    if (length !== before.size || before.size !== after.size || before.mtimeMs !== after.mtimeMs ||
        before.ctimeMs !== after.ctimeMs) throw new Error('Input changed while reading');
    return new TextDecoder('utf-8', {fatal: true}).decode(bytes.subarray(0, length));
  } finally { closeSync(fd); }
}

const terminalSafe = value => String(value).replace(/[\u0000-\u001f\u007f-\u009f\u2028-\u202e\u2066-\u2069]/gu,
  character => '\\u' + character.codePointAt(0).toString(16).padStart(4, '0'));

export function formatReport(report) {
  const lines = ['Verification scheduling candidates (read only)',
    `${report.summary.occurrences} declared occurrences; ${report.summary.opaqueOccurrences} opaque`,
    `${report.summary.suspected} suspected pairs; ${report.summary.unknown} unknown; ${report.summary.different} different`,
    'Action identity unavailable. No equivalence proven; no evidence reuse, skipping or test removal.',
    'Local definitions are alternative entrypoints, not observed additional CI executions.'];
  const byId = new Map(report.actions.map(action => [action.id, action]));
  for (const pair of report.comparisons.filter(item => item.invocationEquality === 'proven')) {
    const label = id => {
      const action = byId.get(id), location = action.source[0];
      return `${terminalSafe(action.job)} (${terminalSafe(location.path)}:${location.line ?? '?'})`;
    };
    lines.push(`${pair.equivalence}: ${label(pair.left)} <> ${label(pair.right)}`,
      `  ${byId.get(pair.left).invocation.argv.map(terminalSafe).join(' ')}`,
      `  ${pair.reasons[0]}${pair.differences.length ? ': ' + pair.differences.join(', ') : ''}`);
  }
  lines.push('Use --json for all occurrences, source chains, opaque blocks and near-match differences.');
  return lines.join('\n') + '\n';
}

export function main(args) {
  if (args.length === 1 && args[0] === '--help') { console.log(usage); return; }
  const options = {root: fileURLToPath(new URL('../', import.meta.url)), workflow: '.github/workflows/ci.yml', json: false};
  const seen = new Set();
  for (let i = 0; i < args.length; i++) {
    const flag = args[i];
    if (!['--root', '--workflow', '--json'].includes(flag) || seen.has(flag)) throw new Error(usage);
    seen.add(flag);
    if (flag === '--json') options.json = true;
    else {
      const value = args[++i];
      if (!value || value.startsWith('--')) throw new Error(usage);
      options[flag.slice(2)] = value;
    }
  }
  const root = resolve(options.root), workflowPath = resolve(root, options.workflow);
  const report = inventory({workflowText: readText(workflowPath),
    workflowPath: relative(root, workflowPath), packageText: readText(join(root, 'package.json')),
    localRunnerText: readText(join(root, 'scripts/local-checks.mjs')),
    toolchainText: readText(join(root, 'toolchain.json'))});
  process.stdout.write(options.json ? JSON.stringify(report, null, 2) + '\n' : formatReport(report));
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { main(process.argv.slice(2)); }
  catch (error) { console.error(terminalSafe(error.message)); process.exitCode = 1; }
}
