import test from 'node:test';
import assert from 'node:assert/strict';
import {readNativeSymbols} from './native-code-inspection.mjs';

// Actual subprocess output transport, not a scientific artifact or code proof.
const largeSymbolEmitter=`
const {writeSync}=require('node:fs');
writeSync(1,'00001000 T wanted\\n');
const line='00001005 t .unrelated'+ 'x'.repeat(1000)+'$bb0\\n';
const chunk=line.repeat(1024);
for(let i=0;i<36;i++)writeSync(1,chunk);
writeSync(1,'00001010 T successor\\n');`;
test('Native symbol reader streams irrelevant output beyond the old whole-output buffer',()=>{
  assert.equal(readNativeSymbols(process.execPath,['-e',largeSymbolEmitter],{names:['wanted']}),
    '00001000 T wanted\n00001010 T successor\n');
});

import {runCodeInspection} from './native-code-inspection.mjs';
import {nativeFunctionEntries,nativeFunctionRanges} from './native-code-disassembly.mjs';
import {codeSymbols,providerSymbolText} from './provider-callback-code.mjs';
const emitter=text=>['-e',`process.stdout.write(${JSON.stringify(text)})`];
const inspect=(text,selection={names:['wanted']})=>readNativeSymbols(process.execPath,emitter(text),selection);
const failure=(action,code,status)=>assert.throws(action,error=>{
  assert.equal(error.code,'ERR_NATIVE_CODE_INSPECTION');
  assert.equal(error.details.code,code);
  if(status!==undefined)assert.equal(error.details.status,status);
  return true;
});
test('filtered symbols retain exact provider identities and every selected range end',()=>{
  const text='00000100 T wanted\n00000100 t alias\n00000101 t .wanted$bb0\n'+
    '00000110 t foreign_next\n00000120 T __M0connectors5local4make\n'+
    '00000121 t __M0connectors5local4make$bb1\n00000130 T foreign_end\n'+
    '00000140 T helper_suffix\n00000150 T last\n';
  const selected=inspect(text,{names:['wanted'],suffixes:['helper_suffix']});
  assert.deepEqual([...codeSymbols(providerSymbolText(selected))],[...codeSymbols(providerSymbolText(text))]);
  const names=['wanted','__M0connectors5local4make','helper_suffix'];
  assert.deepEqual(nativeFunctionRanges(nativeFunctionEntries(selected),names),
    nativeFunctionRanges(nativeFunctionEntries(text),names));
  assert(!selected.includes(' t alias'));
  assert(selected.includes('__M0connectors5local4make$bb1'));
});
test('shared symbol runner preserves argv boundaries and literal paths without a shell',()=>{
  const path='object with spaces;$(must-not-run).o';
  const script=`if(JSON.stringify(process.argv.slice(1))!==JSON.stringify(['-n',${JSON.stringify(path)}]))process.exit(17);process.stdout.write('100 T wanted\\n110 T end\\n');`;
  assert.equal(readNativeSymbols(process.execPath,['-e',script,'--','-n',path],{names:['wanted']}),
    '100 T wanted\n110 T end\n');
});
test('64bit addresses, aliases and duplicate selected identities preserve old refusal cuts',()=>{
  const text='20000000000001 T wanted\n20000000000001 T alias\n20000000000011 T end\n';
  const output=inspect(text,{names:['wanted','alias']});
  assert.throws(()=>nativeFunctionRanges(nativeFunctionEntries(output),['wanted','alias']),/Overlapping/);
  assert.equal(nativeFunctionRanges(nativeFunctionEntries(inspect(text)),['wanted'])[0].end,0x20000000000011n);
  assert.throws(()=>nativeFunctionRanges(nativeFunctionEntries(inspect('100 T wanted\n100 T wanted\n110 T end\n')),['wanted']),/duplicate/);
  assert.throws(()=>nativeFunctionRanges(nativeFunctionEntries(inspect('100 T wanted\n')),['wanted']),/range end/);
});
test('regressive unrelated real functions cannot disappear behind the filter',()=>{
  failure(()=>inspect('100 T wanted\n200 T end\n010 T unselected\n'),'ERR_NATIVE_SYMBOL_ORDER');
});
test('malformed, partial or invalid UTF8 output cannot become accepted symbol evidence',()=>{
  failure(()=>inspect('100 T wanted\nnot a symbol\n'),'ERR_NATIVE_SYMBOL_MALFORMED');
  failure(()=>inspect('100 T wanted'),'ERR_NATIVE_SYMBOL_TRUNCATED',0);
  failure(()=>readNativeSymbols(process.execPath,['-e',"process.stdout.write(Buffer.from([255,10]))"],{names:['wanted']}),'ERR_NATIVE_SYMBOL_ENCODING');
  failure(()=>inspect('100 T unrelated\n'),'ERR_NATIVE_SYMBOL_MISSING',0);
});
test('chunk-split UTF8 symbols preserve exact original bytes',()=>{
  const name='helper_\u{1f600}';
  const text=`100 T ${name}\n110 T end\n`;
  const script=`const b=Buffer.from(${JSON.stringify(text)});for(const byte of b)require('node:fs').writeSync(1,Buffer.from([byte]));`;
  assert.equal(readNativeSymbols(process.execPath,['-e',script],{names:[name]}),text);
});
test('valid stdout never hides a nonzero tool exit, missing tool or inspection signal',()=>{
  failure(()=>readNativeSymbols(process.execPath,['-e',"process.stdout.write('100 T wanted\\n110 T end\\n');process.exit(7)"],{names:['wanted']}),'ERR_NATIVE_INSPECTION_EXIT',7);
  failure(()=>readNativeSymbols('/actql-missing-code-inspection-tool',[],{names:['wanted']}),'ENOENT');
  assert.throws(()=>readNativeSymbols(process.execPath,['-e',"process.kill(process.pid,'SIGTERM')"],{names:['wanted']}),error=>{
    assert.equal(error.details.code,'ERR_NATIVE_INSPECTION_EXIT');assert.equal(error.details.signal,'SIGTERM');return true;
  });
});
test('symbol command deadline is enforced and reported separately from output exhaustion',()=>{
  failure(()=>readNativeSymbols(process.execPath,['-e','setInterval(()=>{},1000)'],{names:['wanted']},{timeout:50}),
    'ERR_NATIVE_INSPECTION_TIMEOUT');
  failure(()=>runCodeInspection(process.execPath,['-e','setInterval(()=>{},1000)'],{timeout:50}),'ETIMEDOUT');
});
test('retained symbols, a single line and stderr keep the existing finite output envelope',()=>{
  const large="const {writeSync}=require('node:fs');const s='00001000 t __M0connectors5local4'+ 'x'.repeat(1000)+'\\n';for(let i=0;i<36;i++)writeSync(1,s.repeat(1024));";
  failure(()=>readNativeSymbols(process.execPath,['-e',large],{names:['wanted']}),'ERR_NATIVE_SYMBOL_OUTPUT_LIMIT');
  const line="const{writeSync}=require('node:fs');for(let i=0;i<34;i++)writeSync(1,'x'.repeat(1024*1024));";
  failure(()=>readNativeSymbols(process.execPath,['-e',line],{names:['wanted']}),'ERR_NATIVE_SYMBOL_LINE_LIMIT');
  const stderr="const{writeSync}=require('node:fs');for(let i=0;i<34;i++)writeSync(2,'x'.repeat(1024*1024));";
  failure(()=>readNativeSymbols(process.execPath,['-e',stderr],{names:['wanted']}),'ERR_NATIVE_INSPECTION_STDERR_LIMIT');
});
test('ordinary bounded disassembly commands still require zero exit and retain safe failure metadata',()=>{
  assert.equal(runCodeInspection(process.execPath,['-e',"process.stdout.write('disassembly\\n')"]),'disassembly\n');
  assert.throws(()=>runCodeInspection(process.execPath,['-e',"process.stderr.write('opaque must not print');process.exit(9)"]),error=>{
    assert.equal(error.details.status,9);assert.equal(error.details.stderrBytes,21);
    assert(!error.message.includes('opaque must not print'));return true;
  });
});
