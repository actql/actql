// Run the actual production Native codec in a small test-only module. No CLI,
// transport, engine or Host implementation is substituted or imported.
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {buildClientHostWire} from './generate-client-host-wire.mjs';
import {runFocusedTests} from './test-execution.mjs';
import {publicWireLanguageVectors, wireConnection} from './fixtures/public-wire-language-vectors.mjs';

const root=fileURLToPath(new URL('../',import.meta.url));
const q=JSON.stringify;
const hash=(bytes: string | Uint8Array)=>createHash('sha256').update(bytes).digest('hex');
type NativeVector = (typeof publicWireLanguageVectors)[number];
const functions=['json_text','same_cancellation_target','same_cancellation_reference','valid_cancellation_outcome'];
export function originalNativeFunctions(source: string) {
  return functions.map(name=>{
    const needle=`\nfn ${name}(`;
    const start=source.indexOf(needle);
    if(start<0 || source.indexOf(needle,start+needle.length)!==-1)throw Error('MissingOrAmbiguousNativeWireFunction:'+name);
    const end=source.indexOf('\n///|',start);
    if(end<0)throw Error('UnterminatedNativeWireFunction:'+name);
    return '///|'+source.slice(start,end)+'\n';
  }).join('\n');
}
function call(entry: NativeVector) {
 switch(entry.operation) {
  case 'profile':return `wire_profile_issue(value, selected) is None`;
  case 'admission':return 'wire_admission(value, selected)';
  case 'run_ref':return 'wire_run_ref_shape(value)';
  case 'lookup':case 'held':return `match expected { String(text) => wire_${entry.operation==='lookup'?'request_lookup':'held'}(value, text); _ => false }`;
  case 'cancellation':return 'valid_cancellation_outcome(value, expected)';
  case 'check_outcome':return 'vector_check_observation(value)';
  default:throw Error('UnknownIndependentNativeVector');
 }
}
export function nativeVectorTests(vectors: readonly NativeVector[]) {
 return vectors.map(entry=>`///|
test ${q('public wire: '+entry.name)} {
  let actual = try {
    let value = @json.parse(${q(entry.valueJSON)})
${['profile','admission'].includes(entry.operation) ? '    let selected = @json.parse('+q(q(wireConnection))+')' : ''}
${['lookup','held','cancellation'].includes(entry.operation) ? '    let expected = @json.parse('+q(entry.expectedJSON ?? q(entry.requestId ?? null))+')' : ''}
    ${call(entry)}
  } catch { _ => false }
  assert_eq(actual, ${entry.expected})
}
`).join('\n');
}
export async function prepareNativeWireVectors(parent: string) {
 await mkdir(parent,{recursive:true});
 const scratch=await mkdtemp(join(parent,'native-wire-'));
 const path=join(scratch,'codec');await mkdir(path);
 const codecSource='src/cmd/native_client/wire.generated.mbt';
 const callerSource='src/cmd/native_client/main.mbt';
 const inputPaths=[codecSource,callerSource,'scripts/fixtures/public-wire-language-vectors.mts',
  'scripts/fixtures/public-wire-language-vectors.mjs','toolchain.json','spec/contracts/actql-client-host.json',
  'spec/contracts/actql-protocol-schemas.json','scripts/generate-native-client-wire.mjs',
  'scripts/generate-client-host-wire.mjs','scripts/client-check-report-rules.mjs',
  'scripts/generate-native-client-wire.mts','scripts/generate-client-host-wire.mts',
  'scripts/client-check-report-rules.mts','scripts/prepare-native-public-wire-vectors.mts'];
 const inputs: {path: string; sha256: string; bytes: number}[]=[];
 for(const file of inputPaths) {
  const bytes=await readFile(join(root,file));inputs.push({path:file,sha256:hash(bytes),bytes:bytes.length});
 }
 const codec=await readFile(join(root,codecSource));
 const registry=JSON.parse(await readFile(join(root,'spec/contracts/actql-client-host.json'),'utf8')) as Parameters<typeof buildClientHostWire>[0];
 const protocol=JSON.parse(await readFile(join(root,'spec/contracts/actql-protocol-schemas.json'),'utf8')) as Parameters<typeof buildClientHostWire>[1];
 const generated=buildClientHostWire(registry,protocol);
 if(generated.native!==codec.toString('utf8'))throw Error('StaleNativePublicWireCodec');
 const checkOutcome=generated.nativeCheckOutcome;
 if(typeof checkOutcome!=='string' || !/^wire_[a-z0-9_]+$/u.test(checkOutcome))throw Error('InvalidGeneratedCheckEntry');
 const observationAdapter=`///|\nfn vector_check_observation(value : Json) -> Bool {\n  ${checkOutcome}(value)\n}\n`;
 const caller=originalNativeFunctions(await readFile(join(root,callerSource),'utf8'));
 await writeFile(join(scratch,'moon.mod'),'name = "actql/wire_conformance"\nversion = "0.0.0"\nsupported_targets = "native"\n');
 await writeFile(join(path,'moon.pkg'),'import { "moonbitlang/core/json" }\noptions(link: { "native": { "cc-flags": "-O0" } })\n');
 await writeFile(join(path,'wire.generated.mbt'),codec);
 await writeFile(join(path,'original_cancellation.mbt'),caller);
 await writeFile(join(path,'language_vectors_wbtest.mbt'),observationAdapter+'\n'+nativeVectorTests(publicWireLanguageVectors));
 await writeFile(join(scratch,'inputs.json'),q({qualification:'Exact production generated codec and selected original cancellation functions; isolated actual Native, no CLI/Host/Engine acceptance.',inputs,copiedCodecSha256:hash(codec),copiedCallerSha256:hash(caller),expectedCases:publicWireLanguageVectors.length})+'\n');
 console.log('Native public-wire scratch: '+scratch);
 return scratch;
}
if(process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 const scratch=await prepareNativeWireVectors(join(root,'_build','public-wire-language'));
 if(!process.argv.includes('--prepare-only'))process.exitCode=runFocusedTests('moon',['--target','native','-j','1'],{cwd:scratch});
}
