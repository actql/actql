import {build} from 'vite';
import {createHash} from 'node:crypto';
import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';

const root = process.cwd(), configFile = resolve('packages/explorer-ui/vite.config.mts');
const original = readFileSync('packages/explorer-ui/dist/plan-explorer.js', 'utf8');
const digest = value => createHash('sha256').update(value).digest('hex');
const directory = resolve('_build/interface-evidence/vite-output-context');
mkdirSync(directory, {recursive: true});
const observations = [];
for (const [name, cwd] of [['repository', root], ['manifest', resolve('packages/explorer-ui')]]) {
  const result = await build({configFile, configLoader: 'native', logLevel: 'silent',
    build: {write: false, emptyOutDir: false, reportCompressedSize: false,
      rolldownOptions: {cwd}}});
  const code = (Array.isArray(result) ? result : [result]).flatMap(value => value.output)
    .find(value => value.fileName === 'plan-explorer.js').code;
  writeFileSync(resolve(directory, `${name}.js`), code, {mode: 0o600});
  const actual = original.split('\n'), candidate = code.split('\n');
  observations.push({name, originalSha256: digest(original), candidateSha256: digest(code),
    same: original === code, firstDifferentLine: actual.findIndex((line, index) => line !== candidate[index]) + 1});
}
writeFileSync(resolve(directory, 'observations.json'), JSON.stringify(observations, null, 2), {mode: 0o600});
console.log(JSON.stringify(observations));
