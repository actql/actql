// Source-only package producers borrow compiler dependencies, then emit their
// own copied sources before entering any prepack/tool module. No prior emit,
// source checkout runtime or successful build receipt is imported here.
import {existsSync} from 'node:fs';
import {symlink} from 'node:fs/promises';
import {join} from 'node:path';

type CopiedCommand = (command: string, args: readonly string[], cwd: string,
  environment: NodeJS.ProcessEnv, timeout: number) => unknown | Promise<unknown>;

export async function prepareCopiedTypeScript({source, root, environment, run}: {
  source: string;
  root: string;
  environment: NodeJS.ProcessEnv;
  run: CopiedCommand;
}): Promise<void> {
  // Preserve the existing fresh-only tool link. EEXIST or a failed compiler
  // is an original failure; neither permits prepack or a stale-output fallback.
  await symlink(join(source, 'node_modules'), join(root, 'node_modules'), 'dir');
  // The optional provider has an independent locked installation. A copied
  // provider source must resolve its installed declarations as the donor does.
  const provider = 'packages/provider-ai-sdk';
  const providerDependencies = join(source, provider, 'node_modules');
  if (existsSync(join(root, provider, 'package.json')) && existsSync(providerDependencies)) {
    await symlink(providerDependencies, join(root, provider, 'node_modules'), 'dir');
  }
  await run('npm', ['run', 'build:typescript'], root, environment, 180_000);
}
