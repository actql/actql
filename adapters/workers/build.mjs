import {build} from 'esbuild';
import {mkdirSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {checkWorkersArtifact, conformanceModules} from './artifact.mjs';

export async function buildConformance() {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const output = `${root}_build/workers`;
  mkdirSync(output, {recursive:true});
  const result = await build({
    absWorkingDir:root, entryPoints:['adapters/workers/conformance.mjs'],
    bundle:true, platform:'browser', format:'esm', target:'es2022',
    metafile:true, write:false, outfile:`${output}/conformance.mjs`,
  });
  const source = result.outputFiles[0].text;
  checkWorkersArtifact(result.metafile, source, conformanceModules);
  writeFileSync(`${output}/conformance.mjs`, source);
  writeFileSync(`${output}/metafile.json`, JSON.stringify(result.metafile,null,2));
  return {source, metafile:result.metafile, bytes:result.outputFiles[0].contents.length};
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const {bytes, metafile} = await buildConformance();
  console.log(JSON.stringify({bytes, modules:Object.keys(metafile.inputs)}));
}
