import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const inventory=JSON.parse(readFileSync(path.join(root,'scripts/fixtures/closed-values-context-carrier-sites.json'),'utf8'));
test('fixed acyclic scaffold carrier source inventory remains matched',()=>{
 let total=0,slots=0;
 for(const row of inventory.rows){
  const source=readFileSync(path.join(root,row.path),'utf8').replace(/\/\/[^\n]*|"(?:\\.|[^"\\])*"/g,'');
  const stack=[],arities=[];
  for(const char of source){
   if(char==='(')stack.push(1);
   else if(char===','&&stack.length)stack[stack.length-1]++;
   else if(char===')'){assert.ok(stack.length,row.path);arities.push(stack.pop());}
  }
  assert.equal(stack.length,0,row.path);
  assert.equal(arities.length,row.sites,row.path);
  assert.equal(arities.reduce((a,b)=>a+b,0),row.payload_slots_upper,row.path);
  total+=row.sites*row.live_multiplier;slots+=row.payload_slots_upper*row.live_multiplier;
 }
 const helper=readFileSync(path.join(root,'src/program_check/closed_values_local_owner_layout.mbt'),'utf8');
 assert.ok(helper.includes(`let sites = ${total}L`));
 assert.ok(helper.includes(`let payload_slots = ${slots}L`));
 assert.equal(total,inventory.sites);assert.equal(slots,inventory.payload_slots_upper);
});
