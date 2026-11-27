import {execFileSync} from 'node:child_process';
import {existsSync} from 'node:fs';
import {dirname, isAbsolute, join, relative, resolve, sep} from 'node:path';

const toolingAuthor = /\.[cm]ts$/u;
const declarationFile = /\.d\.[cm]ts$/u;
const toolingTest = /\.test\.[cm]ts$/u;

async function toolingOutputs(root: string) {
  const {default: ts} = await import('typescript');
  const file = join(root, 'tsconfig.tooling.json');
  const project = ts.readConfigFile(file, ts.sys.readFile);
  if (project.error) return () => undefined;
  const config = ts.parseJsonConfigFileContent(project.config, ts.sys, root, undefined, file);
  if (config.errors.length || config.options.noEmit || config.options.emitDeclarationOnly ||
      config.options.outDir || config.options.outFile) {
    return () => undefined;
  }
  const inputs = new Set(config.fileNames.map(file => resolve(root, file)));
  return (author: string) => {
    const input = resolve(root, author);
    if (!inputs.has(input)) return undefined;
    const output = ts.getOutputFileNames(config, input, !ts.sys.useCaseSensitiveFileNames)
      .find(path => /\.[cm]js$/u.test(path));
    if (!output) return undefined;
    const local = relative(root, output);
    return isAbsolute(local) || local === '..' || local.startsWith('..' + sep) ? undefined : local;
  };
}

const areas: readonly [RegExp, readonly string[]][] = [
  [/^scripts\/packed-client-packages/u, ['client-packages', 'client-distribution', 'client-packed', 'client-packed-composition']],
  [/^scripts\/(build-runtime-packages|test-runtime-package-build|build-local-node|build-run-host-core|build-remote-(coordinator|transfer)-package)|^packages\/(run-host-core|coordinator-core|transfer-core)\//u, ['host']],
  [/^\.github\/|^scripts\/local-checks(?:[-.])/u, ['lint']],
  [/^src\//u, ['lint', 'core']],
  [/^(spec|docs)\/|\.md$/u, ['spec']],
  [/^adapters\/connectors\/salesforce\//u, ['client-distribution', 'client-packed', 'client-packed-composition', 'client-salesforce']],
  [/^adapters\/connectors\/duckdb\/node\//u, ['duckdb-node']],
  [/^adapters\/workers\/|workers/u, ['workers']],
  [/^packages\/(sdk|client-wire|node|local-node)\/|^scripts\/test-(packed(?!-resident-materials)|node-client|native-client)/u,
    ['client-distribution', 'client-packed', 'client-packed-composition', 'client-salesforce']],
  [/^adapters\/host-node\/(client|embedded-local|remote|captured|installed)/u,
    ['client-distribution', 'client-packed', 'client-packed-composition', 'client-salesforce', 'host']],
  [/^adapters\/(host-common|host-node|store-local|site-node|local-node)\//u,
    ['host']],
  [/^(src\/cmd|src\/platform_native)\/|^scripts\/test-native|^scripts\/test-packed-resident-materials/u, ['native']],
  [/^benchmarks\//u, ['host', 'native']],
  [/^scripts\/.*(connector|duckdb-environment)/u, ['connector-addition']],
];

// One known admission-fixture edge, not a general reverse-dependency map.
// Keep these direct inputs and the output aligned with infer-host-fixtures.mjs;
// the registry path is the current actql-aoa.json pipeline_registry_file.
const inferAdmissionPaths = new Set([
  'scripts/infer-host-fixtures.mjs',
  'scripts/check-canonical-json.mjs',
  'spec/contracts/actql-aoa.json',
  'spec/dependencies/aoa-pipeline-registry.json',
  'spec/local-check-environment.json',
  'src/stage_results/infer_program_test.mbt',
  'src/run_publication_host/client_infer_prefix_wbtest.mbt',
  'src/client_infer_host/fixture.generated_wbtest.mbt',
]);

export async function reportChangedLocalChecks(root: string, base: string, ciOnly: ReadonlyMap<string, string>,
  pipelineJobs: readonly string[], classifyJob: (name: string) => {classification: string; heavy: boolean}) {
  const git = (...args: string[]) => execFileSync('git', args,
    {cwd: root, encoding: 'utf8'}).split('\n');
  const files = [...git('diff', '--name-only', `${base}...HEAD`),
    ...git('diff', '--name-only', 'HEAD'),
    ...git('ls-files', '--others', '--exclude-standard')].filter(Boolean);
  const unique = [...new Set(files)];
  if (unique.length === 0) {
    console.log(`No changes since ${base}.`);
    return;
  }
  const narrow = new Set(['git diff --check']);
  const packages = new Set<string>();
  const related = new Set<string>();
  const typed = unique.filter(file => toolingAuthor.test(file) && !declarationFile.test(file) && existsSync(join(root, file)));
  const outputFor = typed.length ? await toolingOutputs(root) : () => undefined;
  const unmapped = typed.filter(file => !outputFor(file));
  for (const file of unique) {
    if (/\.(mbt|mbti)$|(^|\/)moon\.pkg$/u.test(file) && file.startsWith('src/')) {
      packages.add(dirname(file));
    }
    if (/\.test\.mjs$/u.test(file) && existsSync(join(root, file))) {
      narrow.add(`node scripts/local-checks.mjs test node -- ${file}`);
    } else if (/\.mjs$/u.test(file) && existsSync(join(root, file))) {
      narrow.add(`node --check ${file}`);
      const test = file.replace(/\.mjs$/u, '.test.mjs');
      if (existsSync(join(root, test))) narrow.add(`node scripts/local-checks.mjs test node -- ${test}`);
    }
    const output = toolingAuthor.test(file) && !declarationFile.test(file) ? outputFor(file) : undefined;
    if (output) {
      narrow.add('npm run build:typescript');
      if (toolingTest.test(file)) {
        narrow.add(`node scripts/local-checks.mjs test node -- ${output}`);
      } else {
        narrow.add(`node --check ${output}`);
        const test = outputFor(file.replace(toolingAuthor, '.test$&'));
        if (test) narrow.add(`node scripts/local-checks.mjs test node -- ${test}`);
      }
    }
    if (file.startsWith('proofs/relation-pipeline/')) pipelineJobs.forEach(name => related.add(name));
    for (const [pattern, names] of areas) {
      if (pattern.test(file)) names.forEach(name => related.add(name));
    }
  }
  const inferAdmissionChanged = unique.some(file => inferAdmissionPaths.has(file));
  if (inferAdmissionChanged) {
    narrow.add('node scripts/infer-host-fixtures.mjs');
    narrow.add('node scripts/local-checks.mjs test moon -- --target js -p client_infer_host');
  }
  if (packages.size > 0) {
    narrow.add('moon fmt --check');
    for (const directory of [...packages].sort()) {
      narrow.add(`moon check --target js ${directory}`);
      narrow.add(`node scripts/local-checks.mjs test moon -- --target js -p ${relative('src', directory)}`);
    }
  }
  console.log(`Changed since ${base}: ${unique.length} files\n`);
  console.log('Candidate narrow checks (inspect affected callers and validators too):');
  for (const command of narrow) console.log(`  ${command}`);
  if (unmapped.length) console.log(`  Tooling has no in-place Node emit for: ${unmapped.join(', ')}`);
  if (inferAdmissionChanged) {
    console.log('\nKnown INFER admission dependency (advisory, incomplete):');
    console.log('  The existing read-only freshness check requires the pinned MOON_HOME.');
    console.log('  Inspect the generated admission fixture and affected caller tests; no checks were executed.');
  }
  console.log('\nRelated CI jobs (advisory inspection; not required local execution):');
  for (const name of [...related].sort()) {
    const note = ciOnly.has(name) ? `  # CI only: ${ciOnly.get(name)}`
      : name === 'core' ? '  # select matching-target diagnostics for native-only or FFI changes'
        : '';
    const classification = classifyJob(name);
    const deliberate = classification.classification === 'ci-only' ? ' --dry-run'
      : classification.heavy ? ' --allow-heavy' : '';
    console.log(`  node scripts/local-checks.mjs run ${name}${deliberate}${note}`);
  }
  console.log('\nThese path-based candidates are not complete reverse-dependent coverage.');
  console.log('Follow .agents/skills/actql-local-verification/SKILL.md; broad suites are not local defaults.');
  console.log('After an authorized push, read exact-SHA CI; report executed and unverified coverage separately.');
}
