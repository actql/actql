import test from 'node:test';
import assert from 'node:assert/strict';
import {nativeFunctionEntries,nativeFunctionRanges,extractNativeRanges,disassembleNativeRanges} from './native-code-disassembly.mjs';

const symbols = '100 T first\n101 t .first$bb0\n110 t omitted\n120 T second\n130 T end\n';
const entries = nativeFunctionEntries(symbols);
const marker = 'Disassembly of section .text:\n\n';
const first = `0000000000000100 <first>:
 100: push rbp
0000000000000101 <.first$bb0>:
 101: call 106 <.first$bb0>
 102: R_X86_64_PLT32 moonbit_malloc-0x4
 106: ret
`;
const second = `0000000000000120 <second>:
 120: mov rdi,0x8
 127: ret
`;
const batch = 'native.o: file format elf64-x86-64\n\n'+marker+first+
  '\n0000000000000110 <omitted>:\n 110: call 9000 <unselected>\n\n'+second;

test('one bounded batch preserves the per-function output, labels and relocations',()=>{
  const calls=[];
  const result=disassembleNativeRanges((tool,args)=>{calls.push({tool,args});return batch;},
    '/objdump','native.o',entries,['first','second'],true);
  assert.equal(result,marker+first+'\n'+marker+second);
  assert(!result.includes('unselected'));
  assert.equal(calls.length,1);
  assert.deepEqual(calls[0],{tool:'/objdump',args:['-d','-Mintel','--section=.text','--no-show-raw-insn','-r',
    '--start-address=0x100','--stop-address=0x130','native.o']});
});
test('requested function order is separate from sorted batching order',()=>{
  const result=disassembleNativeRanges(()=>batch,'/objdump','native.o',entries,['second','first'],false);
  assert.equal(result,marker+second+'\n'+marker+first);
  assert.deepEqual(nativeFunctionRanges(entries,['first','second']).map(r=>[r.start,r.end]),
    [[0x100n,0x110n],[0x120n,0x130n]]);
});
test('basic-block labels never shorten a selected function range',()=>{
  assert.deepEqual(entries.map(e=>e[2]),['first','omitted','second','end']);
  assert(extractNativeRanges(batch,nativeFunctionRanges(entries,['first'])).get('first').includes('.first$bb0'));
});
test('duplicate, missing, aliased and unordered ranges reject instead of narrowing scope',()=>{
  for(const names of [[],['first','first'],['missing'],['end']])
    assert.throws(()=>nativeFunctionRanges(entries,names));
  assert.throws(()=>nativeFunctionRanges(nativeFunctionEntries(symbols+'100 T alias\n'),['first']),/Unordered/);
  const aliases=nativeFunctionEntries('100 T first\n100 T alias\n110 T end\n');
  assert.throws(()=>nativeFunctionRanges(aliases,['first','alias']),/Overlapping/);
  assert.throws(()=>nativeFunctionRanges(nativeFunctionEntries(symbols.replace('100 T first','100 T first\n100 T first')),['first']),/Missing or duplicate/);
});
test('changed headers, empty output and extra unaddressed output reject',()=>{
  const ranges=nativeFunctionRanges(entries,['first']);
  for(const text of [batch.replace('<first>','<other>'),batch.replace(marker,''),batch+marker,
    batch+'warning: truncated output\n',marker+'0000000000000100 <first>:\n'])
    assert.throws(()=>extractNativeRanges(text,ranges));
});
test('distant functions split batches and an oversized function is never truncated',()=>{
  const rows=nativeFunctionEntries('100 T first\n110 T next\n30000 T large\n60000 T last\n');
  const calls=[];
  const result=disassembleNativeRanges((tool,args)=>{
    calls.push(args);
    const start=BigInt(args.find(a=>a.startsWith('--start-address')).split('=')[1]);
    const name=start===0x100n?'first':'large';
    return marker+`${start.toString(16)} <${name}>:\n ${start.toString(16)}: ret\n`;
  },'/objdump','native.o',rows,['large','first'],false);
  assert.equal(calls.length,2);
  assert(calls[1].includes('--start-address=0x30000'));
  assert(calls[1].includes('--stop-address=0x60000'));
  assert(result.startsWith(marker+'30000 <large>'));
});
test('64-bit addresses remain exact rather than becoming rounded Number offsets',()=>{
  const rows=nativeFunctionEntries('20000000000001 T first\n20000000000011 T end\n');
  const range=nativeFunctionRanges(rows,['first'])[0];
  assert.equal(range.start,0x20000000000001n);
  assert.equal(range.end,0x20000000000011n);
  assert.equal(extractNativeRanges(marker+'20000000000001 <first>:\n 20000000000001: ret\n',[range]).size,1);
});
test('single-pass extraction rejects regressive addresses and overlapping requested ranges',()=>{
  const ranges=nativeFunctionRanges(entries,['first','second']);
  assert.throws(()=>extractNativeRanges(batch.replace(' 106: ret',' 100: ret'),ranges),/Regressive/);
  assert.throws(()=>extractNativeRanges(batch,[ranges[0],{...ranges[1],start:0x108n}]),/Overlapping/);
  assert.throws(()=>extractNativeRanges(batch,[ranges[0],ranges[0]]),/Duplicate/);
  assert.throws(()=>extractNativeRanges(batch,[{...ranges[0],end:0x100n}]),/Empty/);
});
