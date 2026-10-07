import assert from 'node:assert/strict';
import {readFileSync, existsSync, mkdirSync, writeFileSync, copyFileSync} from 'node:fs';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {scalarSitesX64} from './provider-callback-x64.mjs';
import {hash} from '../../inventory.mjs';

const nm = '/usr/bin/nm';
function toolsFor(platform) {
  assert(['darwin-arm64','linux-x64'].includes(platform),'Unsupported scalar code platform');
  return platform==='darwin-arm64'
    ? {anchorName:'_actql_proof_provider_construction',malloc:'_moonbit_malloc',objdump:'/Library/Developer/CommandLineTools/usr/bin/llvm-objdump'}
    : {anchorName:'actql_proof_provider_construction',malloc:'moonbit_malloc',objdump:'/usr/bin/objdump'};
}
const objectPath = '_build/native/debug/test/connectors/local/__moonbit_link_core__/local.whitebox_test.o';
const exePath = '_build/native/debug/test/connectors/local/local.whitebox_test.exe';
function run(tool, args) {
  const r = spawnSync(tool, args, {encoding:'utf8', timeout:30000, maxBuffer:32*1024*1024});
  assert.equal(r.status, 0, r.stderr || `Code inspection failed: ${tool}`);
  return r.stdout;
}
export function codeSymbols(text) {
  const symbols = new Map();
  for (const line of text.split('\n')) {
    const m = line.match(/^([0-9a-f]+)\s+[tT]\s+(\S+)$/);
    if (m) { assert(!symbols.has(m[2]), 'Duplicate Native symbol'); symbols.set(m[2], BigInt(`0x${m[1]}`)); }
  }
  return symbols;
}
// Deliberately restricted to the pinned debug ARM64 instruction sequence.
// Unknown sequences do not receive a guessed size. Only a direct malloc
// request, SCALAR header and the matching relocation stored at offset zero
// establish a live noncapturing callback's requested extent.
export function scalarSites(text, linkedSymbols) {
  const sites = new Map(); let instructions = [], constructor;
  function finish() {
    if (linkedSymbols) {
      const byAddress=new Map([...linkedSymbols].map(([name,address])=>[address.toString(),name]));
      for(let k=0;k<instructions.length;k++) {
        const ins=instructions[k], branch=ins.op.match(/^bl (0x[0-9a-f]+)/);
        if(branch && byAddress.get(BigInt(branch[1]).toString())==='_moonbit_malloc')
          ins.reloc={kind:'BRANCH26',symbol:'_moonbit_malloc'};
        const page=ins.op.match(/^adrp (x\d+), (0x[0-9a-f]+)/), next=instructions[k+1];
        const offset=next?.op.match(/^add (x\d+), (x\d+), #(0x[0-9a-f]+|[0-9]+)$/);
        if(page && offset && page[1]===offset[1] && page[1]===offset[2]) {
          const address=BigInt(page[2])+BigInt(offset[3]),symbol=byAddress.get(address.toString());
          if(symbol) {
            ins.reloc={kind:'PAGE21',symbol};next.reloc={kind:'PAGEOFF12',symbol};
            next.op=`add ${page[1]}, ${page[1]}, #0x0`;
          }
        }
      }
    }
    for (let i = 1; i < instructions.length; i++) {
      const call = instructions[i];
      if (call.reloc?.kind !== 'BRANCH26' || call.reloc.symbol !== '_moonbit_malloc') continue;
      const request = instructions[i-1].op.match(/^mov\s+x0, #(0x[0-9a-f]+|[0-9]+)$/);
      if (!request) continue;
      let j = i+1, object = 'x0';
      const alias = instructions[j]?.op.match(/^mov\s+(x\d+), x0$/);
      if (alias) { object = alias[1]; j++; }
      const zero = instructions[j++]?.op.match(/^mov\s+(w\d+), #(?:0x)?0$/);
      if (!zero || instructions[j++]?.op !== `stur ${zero[1]}, [${object}, #-0x4]`) continue;
      const page = instructions[j++], offset = instructions[j++], store = instructions[j++];
      const register = page?.op.match(/^adrp\s+(x\d+), /)?.[1];
      if (!register || page.reloc?.kind !== 'PAGE21' || offset?.reloc?.kind !== 'PAGEOFF12' ||
          page.reloc.symbol !== offset.reloc.symbol ||
          offset.op !== `add ${register}, ${register}, #0x0` || store?.op !== `str ${register}, [${object}]`) continue;
      assert.equal(BigInt(request[1]), 8n, 'Scalar callback request is not code-pointer-only');
      const symbol = page.reloc.symbol;
      const site = {constructor, symbol, allocationOffset:(BigInt(`0x${call.address}`)-BigInt(`0x${instructions[0].address}`)).toString(), payloadBytes:8, headerBytes:8, requestedBytes:16};
      const prior = sites.get(symbol);
      assert(!prior || JSON.stringify(prior) === JSON.stringify(site), 'Ambiguous callback allocation site');
      sites.set(symbol, site);
    }
  }
  for (const line of text.split('\n')) {
    const fn = line.match(/^[0-9a-f]+ <([^>]+)>:$/);
    if (fn) {finish(); constructor=fn[1]; instructions=[]; continue;}
    const rel = line.match(/^\s*([0-9a-f]+):\s+ARM64_RELOC_(BRANCH26|PAGE21|PAGEOFF12)\s+(\S+)$/);
    if (rel) {
      const last = instructions.at(-1);
      assert(last && BigInt(`0x${last.address}`) === BigInt(`0x${rel[1]}`), 'Detached Native relocation');
      assert(!last.reloc, 'Duplicate Native relocation');
      last.reloc={kind:rel[2],symbol:rel[3]}; continue;
    }
    const ins = line.match(/^\s*([0-9a-f]+):\s+([a-z][a-z0-9.]*)\s*(.*)$/);
    if (ins) instructions.push({address:ins[1],op:`${ins[2]} ${ins[3].split(';')[0].split(' <')[0].trim()}`.trim().replace(/\s+/g,' ')});
  }
  finish(); return sites;
}
export function inspectScalarCode(facts, symbolText, disassembly, linkedDisassembly, platform='darwin-arm64') {
  const {anchorName}=toolsFor(platform);
  const decode=platform==='linux-x64'?scalarSitesX64:scalarSites;
  const symbols = codeSymbols(symbolText), anchor = symbols.get(anchorName);
  assert(anchor !== undefined, 'Missing constructor observer code anchor');
  const byAddress = new Map();
  for (const [name,address] of symbols) {
    const key=address.toString(); const names=byAddress.get(key) ?? []; names.push(name); byAddress.set(key,names);
  }
  const sites=decode(disassembly);
  const linkedSites=decode(linkedDisassembly,symbols);
  assert.deepEqual([...linkedSites.keys()].sort(),[...sites.keys()].sort(),'Object/linked allocation site sets differ in executed binary');
  for(const [name,site] of sites) assert.deepEqual(linkedSites.get(name),site,'Object allocation site differs from executed binary');
  let maximum=0; const observations=[];
  for (const f of facts) {
    assert(Array.isArray(f.scalarCodes) && f.scalarCodes.length === f.scalarDynamicCallbacks, 'Missing live scalar code identities');
    const identities=new Set(); let bytes=0; const callbacks=[];
    for (const c of f.scalarCodes) {
      assert.match(c.identity,/^[0-9a-f]+$/); assert(!identities.has(c.identity), 'Repeated scalar allocation identity'); identities.add(c.identity);
      assert.match(c.codeDelta,/^-?(0|[1-9][0-9]*)$/);
      const names=byAddress.get((anchor+BigInt(c.codeDelta)).toString()) ?? [];
      const matches=names.filter(name=>sites.has(name));
      assert.equal(matches.length,1,'Live callback lacks an unambiguous generated allocation site');
      const site=sites.get(matches[0]); callbacks.push({identity:c.identity,...site}); bytes+=site.requestedBytes;
    }
    maximum=Math.max(maximum,f.indexedBytes+bytes);
    observations.push({scalarRequestedBytes:bytes,indexedRequestedBytes:f.indexedBytes,pointRequestedBytes:f.indexedBytes+bytes,callbacks});
  }
  assert(observations.length>0,'Missing provider observations');
  return {scope:`dynamic scalar callbacks reachable at the eleven-candidate construction observation on ${platform}`,observations,maxPointRequestedBytes:maximum,
    scalarPayloadBytesMeasured:false,scalarAllocationRequestsEstablished:true,
    completeConstructorLifetimeUpper:false,completeParentUpper:false,completePipelineUpper:false};
}
export function providerSymbolText(text) {
  return text.split('\n').filter(line=>/\s(?:_?actql_proof_provider_construction|_?moonbit_malloc)$/.test(line) ||
    /\s\S*connectors5local\S*$/.test(line)).join('\n')+'\n';
}
export function providerConstructors(names, providerNames) {
  const allowed=new Set([...providerNames.map(p=>p.replaceAll('_','__')),
    'managed__provider','managed__provider__with__inputs','managed__provider__with__numeric',
    'selected__relation__provider_2einner']);
  const constructors=[...names].filter(name=>allowed.has(name.match(/connectors5local[0-9]+(.+)$/)?.[1]));
  assert.equal(constructors.length,allowed.size,'Missing or duplicate generated provider constructors');
  return constructors;
}
function generatedCode(root, object, exe, providerNames, platform) {
  const {anchorName,malloc,objdump}=toolsFor(platform);
  const full=run(nm,['-n',exe]);
  const names=codeSymbols(providerSymbolText(full));
  const constructors=providerConstructors(names.keys(),providerNames);
  const symbols=[...names].filter(([name])=>name===anchorName || name===malloc || name.includes('connectors5local'))
    .map(([name,address])=>`${address.toString(16)} T ${name}`).join('\n')+'\n';
  function dump(file,relocations) {
    if(platform==='darwin-arm64') {
      const raw=run(objdump,[...(relocations?['--reloc']:[]),`--disassemble-symbols=${constructors.join(',')}`,'--no-show-raw-insn',file]);
      assert(raw.includes('Disassembly of section'),'Missing Native disassembly');
      return raw.slice(raw.indexOf('Disassembly of section'));
    }
    // GNU debug symbols have zero size and include basic-block labels. Use
    // finite ranges ending at the next real function, never its first block.
    const all=run(nm,['-n',file]).split('\n').map(l=>l.match(/^([0-9a-f]+)\s+[tT]\s+(\S+)$/))
      .filter(m=>m && !m[2].startsWith('.') && !m[2].includes('$bb'));
    return constructors.map(name=>{
      const matches=all.filter(m=>m[2]===name); assert.equal(matches.length,1,'Missing or duplicate constructor range');
      const start=BigInt('0x'+matches[0][1]);
      const next=all.find(m=>BigInt('0x'+m[1])>start); assert(next,'Missing constructor range end');
      const raw=run(objdump,['-d','-Mintel','--section=.text','--no-show-raw-insn',...(relocations?['-r']:[]),
        `--start-address=0x${start.toString(16)}`,`--stop-address=0x${next[1]}`,file]);
      assert(raw.includes('Disassembly of section'),'Missing Native disassembly');
      return raw.slice(raw.indexOf('Disassembly of section'));
    }).join('\n');
  }
  return {symbols,disassembly:dump(object,true),linkedDisassembly:dump(exe,false),constructors};
}
export function collectScalarCode(root, runtime, providerNames) {
  if(!['darwin-arm64','linux-x64'].includes(runtime.platform)) return {status:'unresolved',reason:'unsupported generated scalar-site platform'};
  const {objdump}=toolsFor(runtime.platform);
  assert(existsSync(objdump),'Missing generated-code inspection tool');
  const object=readFileSync(join(root,objectPath)), objectDigest=hash(object);
  const dir='.artifacts/relation-pipeline/current-chain-native/code';mkdirSync(join(root,dir),{recursive:true});
  const archive=`${dir}/${objectDigest}.o`;
  if(!existsSync(join(root,archive)))copyFileSync(join(root,objectPath),join(root,archive));
  assert.equal(hash(readFileSync(join(root,archive))),objectDigest);
  const generated=generatedCode(root,join(root,archive),join(root,exePath),providerNames,runtime.platform);
  const logs={};
  for(const key of ['symbols','disassembly','linkedDisassembly']) {
    const digest=hash(generated[key]),path=`${dir}/${digest}.${key}`;
    if(!existsSync(join(root,path)))writeFileSync(join(root,path),generated[key],{flag:'wx'});
    logs[key]={path,digest};
  }
  return {status:'established',platform:runtime.platform,objectDigest,archive,logs,constructors:generated.constructors,
    tools:{nm:hash(readFileSync(nm)),objdump:hash(readFileSync(objdump))}};
}
export function auditScalarCode(report, facts, root, read, providerNames) {
  const proof=report.providerCallbackCode; assert(proof,'Missing scalar code correspondence status');
  if(proof.status==='unresolved') {
    assert(!['darwin-arm64','linux-x64'].includes(report.runtime.platform),'Supported scalar code correspondence missing');
    assert.deepEqual(proof,{status:'unresolved',reason:'unsupported generated scalar-site platform'});
    return {status:'unresolved',completeConstructorLifetimeUpper:false};
  }
  assert.equal(proof.status,'established'); assert.equal(proof.platform,report.runtime.platform); const {objdump}=toolsFor(proof.platform);
  assert.match(proof.objectDigest,/^[0-9a-f]{64}$/);
  assert.equal(proof.archive,`.artifacts/relation-pipeline/current-chain-native/code/${proof.objectDigest}.o`);
  assert.equal(hash(read(proof.archive)),proof.objectDigest,'Generated provider object changed');
  const exe=report.archives[exePath]; assert(exe,'Missing executed Native executable');
  assert.deepEqual(proof.tools,{nm:hash(readFileSync(nm)),objdump:hash(readFileSync(objdump))},'Code inspection tool changed');
  const regenerated=generatedCode(root,join(root,proof.archive),join(root,exe),providerNames,proof.platform);
  assert.deepEqual(proof.constructors,regenerated.constructors,'Changed generated constructor selection');
  for(const key of ['symbols','disassembly','linkedDisassembly']) {
    assert.match(proof.logs[key].digest,/^[0-9a-f]{64}$/);
    assert.equal(proof.logs[key].path,`.artifacts/relation-pipeline/current-chain-native/code/${proof.logs[key].digest}.${key}`);
    const text=read(proof.logs[key].path).toString(); assert.equal(hash(text),proof.logs[key].digest);
    assert.equal(text,regenerated[key],'Code observations do not match archived Native bytes');
  }
  return inspectScalarCode(facts,regenerated.symbols,regenerated.disassembly,regenerated.linkedDisassembly,proof.platform);
}
