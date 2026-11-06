#!/usr/bin/env node
// npm starts this small launcher. Every protocol operation runs in Native.
import {createRequire} from 'node:module';
import {readFileSync, lstatSync, realpathSync, writeSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {constants} from 'node:os';
import {installedLocalRuntimeEnvironment} from '../lib/local-runtime.mjs';
import {projectInitArguments, projectInitialAdoptionArguments, scaffoldProject} from '../lib/project-scaffold.mjs';

export function platformKey({platform, arch, glibc}) {
  if (platform === 'darwin' && arch === 'arm64') return 'darwin-arm64';
  if (platform === 'linux' && arch === 'x64' && typeof glibc === 'string' && /^\d+\.\d+(?:\.\d+)?$/u.test(glibc)) return 'linux-x64-gnu';
  throw Object.assign(Error(`Unsupported platform: ${platform}/${arch}; Linux requires identifiable glibc. No alternative binary is used.`), {exitCode: 64});
}

export function macOSProductVersion(query = spawnSync) {
  // Ask the kernel for the actual ProductVersion, not a Darwin-version
  // approximation. Retain sw_vers for systems where that query is unavailable.
  for (const [command, args] of [
    ['/usr/sbin/sysctl', ['-n', 'kern.osproductversion']],
    ['/usr/bin/sw_vers', ['-productVersion']],
  ]) {
    // Compatibility spelling must not make a supported OS look too old.
    // This affects only the metadata query, not the Native child's environment.
    const result = query(command, args, {encoding: 'utf8', maxBuffer: 1024, timeout: 1000,
      env: {...process.env, SYSTEM_VERSION_COMPAT: '0'}});
    if (result.error || result.status !== 0 || result.signal) continue;
    const version = typeof result.stdout === 'string' ? result.stdout.trim() : undefined;
    // The existing ABI admission parses this fact once. A successful malformed
    // reply is refused there, rather than replaced with another service's value.
    return typeof version === 'string' && version.length <= 47 ? version : undefined;
  }
  return undefined;
}

export function admitInstalledBinary({key, expected, metadata, binary, glibc, macOS}) {
  if (!expected || metadata.version !== 'actql-native-cli-artifact/0.1' ||
      metadata.platform !== key || metadata.sourceSha !== expected.sourceSha ||
      metadata.binarySha256 !== expected.binarySha256 ||
      metadata.binaryBytes !== expected.binaryBytes || binary.length !== expected.binaryBytes ||
      createHash('sha256').update(binary).digest('hex') !== expected.binarySha256) {
    throw Object.assign(Error('Native artifact identity mismatch; reinstall the fixed package cohort.'), {exitCode: 65});
  }
  if (key === 'darwin-arm64') {
    const parse = value => typeof value === 'string' && /^\d+\.\d+(?:\.\d+)?$/u.test(value)
      ? [...value.split('.').map(Number), 0].slice(0, 3) : null;
    const required = parse(metadata.abi.minimumMacOS), actual = parse(macOS);
    const difference = required && actual && actual.map((v, i) => v - required[i]).find(v => v !== 0);
    if (!required || !actual || difference < 0) {
      throw Object.assign(Error(`Unsupported macOS ${macOS}; Native executable requires at least ${metadata.abi.minimumMacOS}.`), {exitCode: 64});
    }
  }
  if (key === 'linux-x64-gnu') {
    const parse = value => typeof value === 'string' && /^\d+\.\d+$/u.test(value) ? value.split('.').map(Number) : null;
    const required = parse(metadata.abi.minimumGlibc), actual = parse(glibc?.split('.').slice(0, 2).join('.'));
    if (!required || !actual || actual[0] < required[0] || actual[0] === required[0] && actual[1] < required[1]) {
      throw Object.assign(Error(`Unsupported glibc ${glibc}; Native executable requires at least ${metadata.abi.minimumGlibc}.`), {exitCode: 64});
    }
  }
}

export function launch(args) {
  const timingStart = process.env.ACTQL_NATIVE_TIMINGS === '1' ? process.hrtime.bigint() : null;
  const initialization = projectInitArguments(args);
  if (initialization?.help) {
    console.log('Usage: actql init [--template churn-risk-mock|deal-review-mock] [<directory>]');
    return 0;
  }
  const glibc = process.platform === 'linux' ? process.report.getReport().header.glibcVersionRuntime : undefined;
  const key = platformKey({platform: process.platform, arch: process.arch, glibc});
  const packageRoot = fileURLToPath(new URL('../', import.meta.url));
  const platforms = JSON.parse(readFileSync(join(packageRoot, 'platforms.json'), 'utf8'));
  const expected = platforms[key];
  if (!expected) throw Object.assign(Error(`Native package ${key} has not been included in this release.`), {exitCode: 69});
  let installed;
  try {installed = dirname(createRequire(import.meta.url).resolve(`${expected.package}/package.json`));}
  catch {throw Object.assign(Error(`Missing ${expected.package}; install actql with optional dependencies enabled. No download or source build is attempted.`), {exitCode: 69});}
  const executable = join(installed, 'bin/actql-native-client');
  const stat = lstatSync(executable);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 64 * 1024 * 1024 || !(stat.mode & 0o111)) {
    throw Object.assign(Error('Native executable is missing, non-regular or not executable.'), {exitCode: 65});
  }
  const metadata = JSON.parse(readFileSync(join(installed, 'artifact.json'), 'utf8'));
  const macOS = process.platform === 'darwin' ? macOSProductVersion() : undefined;
  admitInstalledBinary({key, expected, metadata,
    binary: readFileSync(executable), glibc, macOS});
  const environment = {...process.env};
  delete environment.ACTQL_NATIVE_LOCAL_RUNTIME;
  let selectedEnvironment = environment;
  if (metadata.localRuntime !== undefined || expected.localRuntimeSha256 !== undefined) {
    selectedEnvironment = installedLocalRuntimeEnvironment({root: installed,
      expected: {...expected, platform: key}, metadata: metadata.localRuntime,
      platformFacts: {macOS, glibc}, environment});
  }
  // The documented command uses the same admitted Native version entrance.
  // Native supplies the answer; no project, Host or second parser is created.
  let selectedArguments = args.length === 1 && args[0] === 'version' ? ['--version'] : args;
  if (initialization) {
    // This known package capability failure must precede all project writes.
    // The inherited selector was removed above; only admitted installation
    // metadata can supply it. Native still owns physical/runtime admission.
    if (selectedEnvironment.ACTQL_NATIVE_LOCAL_RUNTIME === undefined) {
      throw Object.assign(Error(`Packaged Local runtime is unavailable for ${key}; actql init requires it. No project files were created. Remote commands remain available.`), {exitCode: 69});
    }
    // Preparation creates no state or key. Only the same admitted Native image
    // may adopt the explicit project Store through its existing installation
    // Owner. Failure leaves partial files and original cleanup responsibilities.
    const project = scaffoldProject(initialization.directory, initialization.template);
    selectedArguments = projectInitialAdoptionArguments(project);
  }
  const childStart = timingStart === null ? null : process.hrtime.bigint();
  const child = spawnSync(executable, selectedArguments, {stdio: 'inherit', env: selectedEnvironment});
  if (timingStart !== null) {
    // Observational only: missing diagnostics cannot change the Native result
    // or acknowledge child cleanup. Imports and OS process creation precede
    // this entry; the external consumer measures those separately.
    try {
      const finish = process.hrtime.bigint();
      writeSync(2, 'ACTQL_NATIVE_LAUNCHER_TIMINGS ' + JSON.stringify({
        units: 'nanoseconds',
        preparation: Number(childStart - timingStart),
        child: Number(finish - childStart),
        total: Number(finish - timingStart),
      }) + '\n');
    } catch {}
  }
  if (child.error) throw Object.assign(Error(`Native start failed: ${child.error.code}. Reinstall the fixed package cohort and verify the supported platform.`), {exitCode: 69});
  return child.status ?? 128 + (constants.signals[child.signal] ?? 1);
}

if (process.argv[1] && realpathSync(resolve(process.argv[1])) === fileURLToPath(import.meta.url)) {
  try {process.exitCode = launch(process.argv.slice(2));}
  catch (error) {console.error(`actql: ${error.message}`); process.exitCode = error.exitCode ?? 69;}
}
