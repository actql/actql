import assert from 'node:assert/strict';

// Only the pinned debug compiler's contiguous noncapturing closure sequence
// is accepted. A header or a code address alone does not establish an extent.
export function scalarSitesX64(text, linkedSymbols) {
  const sites=new Map(); let constructor, start, instructions=[];
  const addresses=linkedSymbols && new Map([...linkedSymbols].map(([name,address])=>[address.toString(),name]));
  function finish() {
    for(let k=0;k<instructions.length;k++) {
      const ins=instructions[k];
      if(ins.reloc) {
        const next=instructions[k+1];
        assert(next && ins.reloc.address>=ins.address && ins.reloc.address<next.address,
          'Detached Native relocation');
        assert((ins.op.startsWith('call ') && ins.reloc.kind==='PLT32') ||
          (ins.op.startsWith('lea ') && ins.reloc.kind==='PC32'),'Unexpected Native relocation instruction');
      }
    }
    for(let i=1;i+5<instructions.length;i++) {
      const call=instructions[i], request=instructions[i-1].op.match(/^movabs rdi,(0x[0-9a-f]+)$/);
      let malloc=call.reloc?.symbol;
      if(addresses && /^call [0-9a-f]+$/.test(call.op)) malloc=addresses.get(BigInt('0x'+call.op.slice(5)).toString());
      if(malloc!=='moonbit_malloc' || !request) continue;
      const alias=instructions[i+1].op.match(/^mov (r[a-z0-9]+),rax$/);
      const zero=instructions[i+2].op.match(/^mov (r[a-z0-9]+d),0x0$/);
      if(!alias || !zero || instructions[i+3].op!==`mov DWORD PTR [${alias[1]}-0x4],${zero[1]}`) continue;
      const lea=instructions[i+4], store=instructions[i+5];
      const pointer=lea.op.match(/^lea (r[a-z0-9]+),\[rip([+-])0x([0-9a-f]+)\]$/);
      if(!pointer || ![ `mov QWORD PTR [${alias[1]}],${pointer[1]}`,
        `mov QWORD PTR [${alias[1]}+0x0],${pointer[1]}` ].includes(store.op)) continue;
      let symbol=lea.reloc?.symbol;
      if(addresses) {
        const displacement=BigInt('0x'+pointer[3])*(pointer[2]==='-'?-1n:1n);
        symbol=addresses.get((store.address+displacement).toString());
      }
      if(!symbol) continue;
      assert.equal(BigInt(request[1]),8n,'Scalar callback request is not code-pointer-only');
      const site={constructor,symbol,allocationOffset:(call.address-start).toString(),payloadBytes:8,headerBytes:8,requestedBytes:16};
      const prior=sites.get(symbol);
      assert(!prior || JSON.stringify(prior)===JSON.stringify(site),'Ambiguous callback allocation site');
      sites.set(symbol,site);
    }
  }
  for(const line of text.split('\n')) {
    const fn=line.match(/^([0-9a-f]+) <([^>]+)>:$/);
    if(fn) {
      // Debug basic-block labels are not function boundaries.
      if(fn[2].startsWith('.') || fn[2].includes('$bb')) continue;
      finish(); constructor=fn[2]; start=BigInt('0x'+fn[1]); instructions=[]; continue;
    }
    const relocation=line.match(/^\s*([0-9a-f]+):\s+R_X86_64_(PLT32|PC32)\s+(\S+)-0x4$/);
    if(relocation) {
      const ins=instructions.at(-1); assert(ins && !ins.reloc,'Detached or duplicate Native relocation');
      ins.reloc={address:BigInt('0x'+relocation[1]),kind:relocation[2],symbol:relocation[3]}; continue;
    }
    assert(!/R_X86_64_/.test(line),'Unsupported Native relocation');
    const ins=line.match(/^\s*([0-9a-f]+):\s+([a-z][a-z0-9.]*)\s*(.*)$/);
    if(ins) {
      assert(constructor,'Instruction outside constructor');
      const address=BigInt('0x'+ins[1]); assert(!instructions.length || address>instructions.at(-1).address,'Unordered Native instructions');
      const op=`${ins[2]} ${ins[3].split('#')[0].split(' <')[0].trim()}`.trim().replace(/\s+/g,' ').replace(/,\s*/g,',');
      instructions.push({address,op});
    }
  }
  finish(); return sites;
}
