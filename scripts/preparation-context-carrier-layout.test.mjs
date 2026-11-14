import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const inventory=JSON.parse(readFileSync(path.join(root,'scripts/fixtures/closed-values-context-carrier-sites.json'),'utf8'));
function carrierArities(source){
 source=source.replace(/\/\/[^\n]*|"(?:\\.|[^"\\])*"/g,'');
 const stack=[],arities=[];
 for(const char of source){
  if(char==='(')stack.push(1);
  else if(char===','&&stack.length)stack[stack.length-1]++;
  else if(char===')'){assert.ok(stack.length);arities.push(stack.pop());}
 }
 assert.equal(stack.length,0);
 return arities;
}
test('fixed acyclic scaffold carrier source inventory remains matched',()=>{
 let total=0,slots=0;
 for(const row of inventory.rows){
  const arities=carrierArities(readFileSync(path.join(root,row.path),'utf8'));
  assert.equal(arities.length,row.sites,row.path);
  assert.equal(arities.reduce((a,b)=>a+b,0),row.payload_slots_upper,row.path);
  total+=row.sites*row.live_multiplier;slots+=row.payload_slots_upper*row.live_multiplier;
 }
 const helper=readFileSync(path.join(root,'src/program_check/closed_values_local_owner_layout.mbt'),'utf8');
 assert.ok(helper.includes(`let sites = ${total}L`));
 assert.ok(helper.includes(`let payload_slots = ${slots}L`));
 assert.equal(total,inventory.sites);assert.equal(slots,inventory.payload_slots_upper);
});

test('exact Timestamp comparison adds one conservative site and two payload slots',()=>{
 // Hand-authored expression inventories, not expectations derived from the
 // current product totals. The returned Option and its Some comparison remain
 // counted even though this branch is unreachable on the closed Values route.
 assert.deepEqual(carrierArities('start.compare(end)'),[1]);
 assert.deepEqual(carrierArities('@value.compare_timestamp_text(start, end) == Some(1)'),[2,1]);
 const row=inventory.rows.find(row=>row.path==='src/pipeline_check_context/operation_ranges.mbt');
 const source=readFileSync(path.join(root,row.path),'utf8');
 assert.match(source,/if @value\.compare_timestamp_text\(start, end\) == Some\(1\) \{/);
 assert.equal(createHash('sha256').update(source).digest('hex'),row.source_sha256);
 assert.deepEqual([row.sites,row.payload_slots_upper,row.live_multiplier,row.max_slots],[104,155,1,7]);
 // The existing two-carrier projection adds 2H/3R/4W, hence 88 bytes;
 // neither a new grant nor a measured allocation is inferred from this upper.
 assert.equal(16*2+8*3+8*4,88);
});
