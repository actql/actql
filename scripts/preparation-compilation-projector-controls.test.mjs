import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const root=new URL('../',import.meta.url);
const read=path=>readFileSync(new URL(path,root));
test('fixed compilation projector packet tracks its actual finite helper family',()=>{
  const sources=JSON.parse(read('scripts/fixtures/preparation-compilation-projector-controls.json'));
  for(const [path,hash] of Object.entries(sources)){
    assert.equal(createHash('sha256').update(read(path)).digest('hex'),hash,`${path}: review projector constructor cardinalities`);
  }
  const families=[[112,74,15,148],[18,36,18,116],[16,14,2,32],[2,16,2,42],
    [3,12,1,26],[30,3,1,18],[2,4,15,26],[1,25,11,126],[1,33,21,165],
    [1,11,3,43],[2,3,1,11],[2,7,1,16],[1,7,1,16],[1,20,3,55],[1,12,2,21]];
  const totals=[0,0,0];for(const [calls,...units] of families)units.forEach((n,i)=>totals[i]+=calls*n);
  assert.deepEqual(totals,[9454,2148,20410]);
  assert.equal(totals[0]*16+totals[1]*8+totals[2]*8,331728);
  const source=read('src/client_local_host/preparation_closed_values_projection_scratch.mbt').toString();
  for(const term of ['+ 9454L','+ 2148L','+ 20410L'])assert.ok(source.includes(term));
});
