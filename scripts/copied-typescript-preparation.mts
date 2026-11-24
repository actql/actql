// Source-only package producers borrow compiler dependencies, then emit their
// own copied sources before entering any prepack/tool module. No prior emit,
// source checkout runtime or successful build receipt is imported here.
import {existsSync} from 'node:fs';
import {mkdir, readdir, readlink, realpath, symlink} from 'node:fs/promises';
import {join, relative, sep} from 'node:path';

type CopiedCommand = (command: string, args: readonly string[], cwd: string,
  environment: NodeJS.ProcessEnv, timeout: number) => unknown | Promise<unknown>;

export async function prepareCopiedTypeScript({source, root, environment, run}: {
  source: string;
  root: string;
  environment: NodeJS.ProcessEnv;
  run: CopiedCommand;
}): Promise<void> {
  const sourceRoot = await realpath(source);
  const installed = join(sourceRoot, 'node_modules'), copied = join(root, 'node_modules');
  // A preexisting installation still refuses before any compiler or prepack runs.
  await mkdir(copied);
  for (const name of await readdir(installed)) {
    if (name !== '@actql' && name !== '.bin') await symlink(join(installed, name), join(copied, name));
  }
  const scope = join(installed, '@actql'), copiedScope = join(copied, '@actql');
  if (existsSync(scope)) {
    await mkdir(copiedScope);
    for (const name of await readdir(scope)) {
      const dependency = join(scope, name);
      const path = relative(sourceRoot, await realpath(dependency));
      if (path.startsWith(`packages${sep}`)) {
        // Partial copies only expose the workspace packages they actually contain.
        const local = join(root, path);
        if (existsSync(join(local, 'package.json'))) await symlink(local, join(copiedScope, name), 'dir');
      } else {
        await symlink(dependency, join(copiedScope, name), 'dir');
      }
    }
  }
  // Keep npm's relative bin links so commands for workspace packages stay local too.
  const bins = join(installed, '.bin'), copiedBins = join(copied, '.bin');
  if (existsSync(bins)) {
    await mkdir(copiedBins);
    for (const entry of await readdir(bins, {withFileTypes: true})) {
      const bin = join(bins, entry.name);
      await symlink(entry.isSymbolicLink() ? await readlink(bin) : bin, join(copiedBins, entry.name));
    }
  }
  // The optional provider has an independent locked installation. A copied
  // provider source must resolve its installed declarations as the donor does.
  const provider = 'packages/provider-ai-sdk';
  const providerDependencies = join(source, provider, 'node_modules');
  if (existsSync(join(root, provider, 'package.json')) && existsSync(providerDependencies)) {
    await symlink(providerDependencies, join(root, provider, 'node_modules'), 'dir');
  }
  await run('npm', ['run', 'build:typescript'], root, environment, 180_000);
}
