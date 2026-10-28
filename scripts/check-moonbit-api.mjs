import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const divergence = /^#\n# Package ([^ ]+) (?:has diverging interfaces across backends:|has requested interfaces different from canonical backend)[\s\S]*?^# ------\n?/gm;

// Opaque type binders have no public representation. Their spelling is alpha
// equivalent (including a phantom wildcard), while arity and every other API
// token remain significant. Constrained/structured declarations are untouched.
export function normalizeOpaqueTypeBinders(text) {
  return text.replace(/^type ([A-Za-z_][A-Za-z_0-9]*)\[([A-Za-z_][A-Za-z_0-9]*(?:, [A-Za-z_][A-Za-z_0-9]*)*)\]$/gm,
    (_line, name, binders) => {
      const parts = binders.split(', ');
      if (!parts.every(part => part === '_' || /^[A-Z][A-Za-z_0-9]*$/.test(part))) return _line;
      return `type ${name}[${parts.map((_, index) => `T${index}`).join(', ')}]`;
    });
}

function withoutTargetOnlyPackages(root, report) {
  const moduleText = readFileSync(join(root, 'moon.mod'), 'utf8');
  const moduleName = /^name\s*=\s*"([^"]+)"/m.exec(moduleText)?.[1];
  const sourceRoot = /^source\s*=\s*"([^"]+)"/m.exec(moduleText)?.[1] ?? 'src';
  if (moduleName === undefined) return report;
  return report.replace(divergence, (block, packageName) => {
    const prefix = `${moduleName}/`;
    if (!packageName.startsWith(prefix)) return block;
    const manifestPath = join(
      root,
      sourceRoot,
      packageName.slice(prefix.length),
      'moon.pkg',
    );
    if (!existsSync(manifestPath)) return block;
    const manifest = readFileSync(manifestPath, 'utf8');
    // A package explicitly supporting just Native or Wasm has no canonical
    // JS interface to compare. Keep every multi-target divergence required.
    const targetOnly = /^[ \t]*supported_targets[ \t]*=[ \t]*"(?:native|wasm)"[ \t]*(?:\/\/[^\r\n]*)?$/m.test(manifest);
    if (targetOnly) return '';
    // Compare actual compiler projections, not diff text. No package/target
    // allowlist: only provable opaque binder alpha-renaming can erase a report.
    const relativePackage = packageName.slice(prefix.length);
    const leaf = relativePackage.split('/').at(-1);
    const projections = ['js', 'wasm', 'native'].map(target => join(
      root, '_build', target, 'debug', 'check', relativePackage, `${leaf}.mbti`,
    ));
    if (projections.every(path => existsSync(path))) {
      const normalized = projections.map(path => normalizeOpaqueTypeBinders(readFileSync(path, 'utf8')));
      if (normalized.every(value => value === normalized[0])) return '';
    }
    return block;
  });
}

export function checkInterfaces(root) {
  const report = execFileSync('moon', ['info', '--target', 'js,wasm,native'], {
    cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
  });
  const relevantReport = withoutTargetOnlyPackages(root, report);
  // Pinned moon 94521db reports divergence with exit code zero.
  // The live-tool regression test must accompany toolchain upgrades.
  if (/^# Package .* (?:has diverging interfaces across backends:|has requested interfaces different from canonical backend)/m.test(relevantReport)) {
    throw new Error(
      `Common-core interfaces differ across targets.\n${relevantReport}`,
    );
  }
  const paths = ['src/**/pkg.generated.mbti', 'src/pkg.generated.mbti'];
  try {
    execFileSync('git', ['diff', '--exit-code', '--', ...paths], {
      cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (error) {
    const stdout = error.stdout?.toString?.() ?? '';
    const stderr = error.stderr?.toString?.() ?? '';
    throw new Error(
      `Generated public interfaces differ from tracked files.\n${stdout}${stderr}`,
    );
  }
  const untracked = execFileSync('git', ['ls-files', '--others', '--exclude-standard', '--', ...paths], {
    cwd: root, encoding: 'utf8',
  }).trim();
  if (untracked) throw new Error(`Untracked public interfaces:\n${untracked}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  checkInterfaces(process.cwd());
  console.log('Public interfaces match across targets and tracked files.');
}
