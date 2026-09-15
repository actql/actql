import {build} from 'esbuild';
import {mkdirSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {gzipSync} from 'node:zlib';
import {checkWorkersArtifact, conformanceModules, hostModules} from './artifact.mjs';

async function buildProfile(entry, name, allowed) {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const output = `${root}_build/workers`;
  mkdirSync(output, {recursive:true});
  const result = await build({
    absWorkingDir:root, entryPoints:[entry],
    bundle:true, platform:'browser', format:'esm', target:'es2022',
    metafile:true, write:false, outfile:`${output}/${name}.mjs`,
  });
  const source = result.outputFiles[0].text;
  checkWorkersArtifact(result.metafile, source, allowed);
  writeFileSync(`${output}/${name}.mjs`, source);
  writeFileSync(`${output}/${name}.metafile.json`, JSON.stringify(result.metafile,null,2));
  return {source, metafile:result.metafile, bytes:result.outputFiles[0].contents.length,
    gzipBytes:gzipSync(result.outputFiles[0].contents).length};
}

export const buildConformance = () => buildProfile('adapters/workers/conformance.mjs','conformance',conformanceModules);
export const buildHost = () => buildProfile('adapters/workers/host.mjs','host',hostModules);

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  for (const [profile, build] of [['host',buildHost],['conformance',buildConformance]]) {
    const {bytes, gzipBytes, metafile} = await build();
    console.log(JSON.stringify({profile,bytes,gzipBytes,modules:Object.keys(metafile.inputs)}));
  }
}
