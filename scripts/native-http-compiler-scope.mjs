// Two existing HTTP phases retain their original commands and fixtures but
// cannot share Moon's mutable Core cache or Native output tree concurrently.
import assert from 'node:assert/strict';
import {mkdirSync, readFileSync, realpathSync, symlinkSync, writeFileSync} from 'node:fs';
import {delimiter, join} from 'node:path';
import {copyNativePreparationTools} from './native-preparation-lanes.mjs';

export function prepareNativeHttpCompilerScope(repository, root, {
  env = process.env, platform = process.platform, arch = process.arch,
  copyTools = copyNativePreparationTools,
} = {}) {
  assert.equal(platform, 'darwin', 'The split HTTP consumer belongs to the existing Darwin job');
  assert.equal(arch, 'arm64');
  assert(env.MOON_HOME && env.ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION &&
    env.ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION,
    'Split HTTP phases require the original completed Native and portable preparation');
  repository = realpathSync(repository); root = realpathSync(root);
  const tool = join(root, 'compiler-tool');
  copyTools(env.MOON_HOME, tool, JSON.stringify({
    pin: JSON.parse(readFileSync(join(repository, 'toolchain.json'), 'utf8')),
    platform: `${platform}-${arch}`,
  }));
  const target = join(root, 'native-target');
  mkdirSync(target, {mode: 0o700});
  const moon = join(root, 'native-moon.cjs');
  const bin = join(root, 'compiler-bin'); mkdirSync(bin, {mode: 0o700});
  const original = join(tool, 'bin', 'moon');
  // Keep one actual pinned Moon binary and the original argv. Only its own
  // Native output destination and compiler cache home change; no shell parser,
  // flags, allocator, FFI, runtime limits or process-wide environment change.
  writeFileSync(moon, '#!' + process.execPath + '\n' +
    'const {spawnSync}=require("node:child_process"),{realpathSync}=require("node:fs");\n' +
    `const original=${JSON.stringify(original)},target=${JSON.stringify(target)},home=${JSON.stringify(tool)},bin=${JSON.stringify(bin)},repository=${JSON.stringify(repository)};\n` +
    'const args=process.argv.slice(2);\n' +
    // Moon's own driver generator and private stdlib preparation keep their
    // original explicit destinations. Only repository build/test commands
    // receive this phase's target directory; JS preparation cannot be rebuilt.
    'if(realpathSync(process.cwd())===repository&&["build","test"].includes(args[0])){\n' +
    'if(args.filter(x=>x==="--target").length!==1||args[args.indexOf("--target")+1]!=="native")throw new Error("Original Native Moon command required");\n' +
    'const index=args.indexOf("--target-dir");\n' +
    'if(args.filter(x=>x==="--target-dir").length>1||args.some(x=>x.startsWith("--target-dir="))||index>=0&&args[index+1]!==target)throw new Error("Foreign Native target directory");\n' +
    'if(index<0)args.push("--target-dir",target);}\n' +
    `const env={...process.env,MOON_HOME:home,PATH:bin+${JSON.stringify(delimiter)}+home+"/bin"+${JSON.stringify(delimiter)}+(process.env.PATH??"")};\n` +
    'const result=spawnSync(original,args,{env,stdio:"inherit"});\n' +
    'if(result.error)throw result.error;if(result.signal)process.kill(process.pid,result.signal);\n' +
    'process.exitCode=result.status??1;\n', {flag: 'wx', mode: 0o700});
  symlinkSync(moon, join(bin, 'moon'));
  return {moon, targetDirectory: target, environment: {
    MOON_HOME: tool, PATH: bin + delimiter + join(tool, 'bin') + delimiter + (env.PATH ?? ''),
  }};
}
