import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export function checkInterfaces(root) {
  const report = execFileSync('moon', ['info', '--target', 'js,wasm,native'], {
    cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
  });
  // Pinned moon 94521db reports divergence with exit code zero.
  // The live-tool regression test must accompany toolchain upgrades.
  if (/^# Package .* (?:has diverging interfaces across backends:|has requested interfaces different from canonical backend)/m.test(report)) {
    throw new Error(`Common-core interfaces differ across targets.\n${report}`);
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
