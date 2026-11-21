// Compatibility entrance for the existing selected Linux recipe.
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {assembleNativeLocalRecipe} from './native-cli-local-recipe.mjs';

type LinuxOptions = Omit<Parameters<typeof assembleNativeLocalRecipe>[0], 'platform'>;
type Execute = NonNullable<Parameters<typeof assembleNativeLocalRecipe>[1]>;

export function assembleNativeLinuxLocalRecipe(options: LinuxOptions, execute: Execute = execFileSync) {
  assert(options && !Object.hasOwn(options, 'platform'), 'The Linux entrance fixes its original platform');
  return assembleNativeLocalRecipe({...options, platform: 'linux-x64-gnu'}, execute);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const args = process.argv.slice(2), options: Partial<LinuxOptions> = {};
    const flags = {'--source': 'sourceSha', '--sqlite-component': 'sqliteDirectory',
      '--crypto-component': 'cryptoDirectory', '--output': 'outputDirectory'} as const;
    assert.equal(args.length, 8, 'Required: --source SHA --sqlite-component DIR --crypto-component DIR --output NEW_DIR');
    for (let i = 0; i < args.length; i += 2) {
      const key = flags[args[i] as keyof typeof flags]; assert(key && !options[key] && args[i + 1]); options[key] = args[i + 1];
    }
    console.log(assembleNativeLinuxLocalRecipe(options as LinuxOptions).path);
  } catch (error) { console.error((error as Error).message); process.exitCode = 1; }
}
