import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

export function generateUpdateTargetDataCodec(root, write = false) {
  const owner = readFileSync(join(root, 'src/run_publication_host/client_effect_target_original_data.mbt'), 'utf8');
  const template = readFileSync(join(root, 'scripts/templates/update-target-data-codec.mjs'), 'utf8');
  const material = readFileSync(join(root, 'src/remote_site_protocol/poll.mbt'), 'utf8');
  const materialMaximum = /pub const REMOTE_RUN_MATERIALS_MAX_BYTES\s*:\s*Int\s*=\s*(\d+)/u.exec(material)?.[1];
  if (materialMaximum === undefined) throw new Error('Missing existing Run material ceiling');
  const constant = name => {
    const match = new RegExp(`const ${name}\\s*:\\s*Int\\s*=\\s*(\\d+)`, 'u').exec(owner);
    if (!match) throw new Error(`Missing original Owner codec ceiling: ${name}`);
    return match[1];
  };
  const expected = template.replace('@MAX_BYTES@', constant('CLIENT_EFFECT_TARGET_ORIGINAL_MAX_BYTES'))
    .replace('@MATERIAL_MAX_BYTES@', materialMaximum)
    .replace('@MAX_DEPTH@', constant('CLIENT_EFFECT_TARGET_ORIGINAL_MAX_DEPTH'));
  const path = join(root, 'adapters/host-node/update-target-data.generated.mjs');
  let actual;
  try { actual = readFileSync(path, 'utf8'); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (actual === expected) return;
  if (!write) throw new Error('Stale UPDATE transport codec');
  writeFileSync(path, expected);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (!['--write', '--check'].includes(process.argv[2]) || process.argv.length !== 3) throw new Error('Use --write or --check');
  generateUpdateTargetDataCodec(fileURLToPath(new URL('../', import.meta.url)), process.argv[2] === '--write');
}
