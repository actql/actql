import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const root=new URL('../',import.meta.url);
const read=path=>readFileSync(new URL(path,root),'utf8');

test('selected compilation carrier census pins actual issuer scopes and fixed multiplicities',()=>{
  const rows=JSON.parse(read('scripts/fixtures/preparation-compilation-call-controls.json'));
  let total=0;
  for(const row of rows){
    const source=read(`src/run_publication_host/${row.file}`);
    const clean=source.replace(/^\s*#\|[^\n]*|\/\/[^\n]*|"(?:\\.|[^"\\])*"/gm,match=>' '.repeat(match.length));
    const match=new RegExp(`\\bfn(?:\\[[^\\]]+\\])?\\s+${row.function}\\s*\\(`).exec(clean);
    assert.ok(match,row.function);
    const start=clean.indexOf('{',match.index+match[0].length);let end=start+1,depth=1;
    while(depth){assert.ok(end<clean.length);depth+=(clean[end]==='{')-(clean[end]==='}');end++;}
    assert.equal(createHash('sha256').update(source.slice(start,end)).digest('hex'),row.bodySha256,`${row.function}: review changed allocation/call graph`);
    const sites=[...clean.slice(start,end).matchAll(/\b([A-Z][A-Za-z0-9_]*)\s*\(/g)].length;
    assert.equal(sites,row.sites,row.function);total+=sites*row.multiplicity;
  }
  assert.equal(rows.length,31);assert.equal(total,549);
  const owner=read('src/client_local_host/preparation_compilation_call_controls.mbt');
  assert.match(owner,/record_headers:\s*549L\*3L/);
  assert.match(owner,/reference_slots:\s*549L\*6L/);
  assert.match(owner,/scalar_words:\s*549L\*4L/);
});
