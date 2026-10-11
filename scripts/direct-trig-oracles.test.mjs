import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const bytes=readFileSync(new URL('./fixtures/direct-trig-oracles.json',import.meta.url));
const fixture=JSON.parse(bytes);
const operations=['sin','cos','tan','asin','acos','atan','sinh','cosh','tanh','asinh','acosh','atanh','atan2'];
const bits=value=>{const b=Buffer.alloc(8);b.writeDoubleBE(value);return b.toString('hex');};
const number=hex=>Buffer.from(hex,'hex').readDoubleBE();
function neighbor(value,direction) {
  if(value===0) return direction>0?Number.MIN_VALUE:-Number.MIN_VALUE;
  const b=Buffer.alloc(8);b.writeDoubleBE(value);
  const next=b.readBigUInt64BE()+BigInt((value>0)===(direction>0)?1:-1);
  b.writeBigUInt64BE(next);return b.readDoubleBE();
}

test('direct trig independently frozen MPFR fixture retains its pre-execution identity',()=>{
  assert.equal(createHash('sha256').update(bytes).digest('hex'),'b8b75f437a2ff5fb80bf41183d8bb7e6ab8217d9e28b932544ed4babfc56f3da');
  assert.equal(fixture.version,'actql-direct-trig-oracles/0.1');
  assert.equal(fixture.generator.library,'MPFR');assert.equal(fixture.generator.version,'4.2.2');
  assert.equal(fixture.generator.precisionBits,4096);
  assert.deepEqual(fixture.generator.rounding,['MPFR_RNDD','MPFR_RNDU']);
  assert.equal(fixture.generator.adjacentBinary64Allowance,2);
  assert.match(fixture.generator.scope,/not a universal accuracy guarantee/);
  assert.equal(fixture.vectors.length,131);
  assert.deepEqual([...new Set(fixture.vectors.map(v=>v.operation))].sort(),operations.toSorted());
});

test('direct trig fixture input bits and outward bounds use only the predeclared allowance',()=>{
  for(const v of fixture.vectors) {
    assert.equal(v.inputs.length,v.operation==='atan2'?2:1);
    assert.deepEqual(v.inputs.map(bits),v.inputBits);
    assert.deepEqual(v.directedBounds.map(bits),v.directedBoundBits);
    assert.deepEqual(v.acceptanceBounds.map(bits),v.acceptanceBoundBits);
    assert.ok([...v.inputs,...v.directedBounds,...v.acceptanceBounds].every(Number.isFinite));
    const [lower,upper]=v.directedBounds;
    assert.ok(lower<=upper,v.id);
    assert.ok(lower===upper || neighbor(lower,1)===upper,v.id+' is a tight directed binary64 enclosure');
    if(v.exactCanonicalZero) {
      assert.equal(v.operation,'atan2');assert.equal(Math.abs(v.inputs[0]),5e-324);
      assert.equal(v.inputs[1],Number.MAX_VALUE);
      assert.deepEqual(v.acceptanceBounds,[0,0]);
      assert.deepEqual(v.acceptanceBoundBits,['0000000000000000','0000000000000000']);
    } else {
      assert.deepEqual(v.acceptanceBounds,[neighbor(neighbor(lower,-1),-1),neighbor(neighbor(upper,1),1)]);
    }
  }
});

test('direct trig fixtures cover endpoint neighbors huge arguments both signs and atan2 ordering',()=>{
  const has=(op,...args)=>fixture.vectors.some(v=>v.operation===op&&v.inputs.length===args.length&&v.inputs.every((x,i)=>Object.is(x,args[i])));
  for(const op of ['sin','cos','tan']) {
    for(const input of [1e20,-1e20,1e100,-1e100,1e300,-1e300,Number.MAX_VALUE,-Number.MAX_VALUE]) assert.ok(has(op,input));
    const halfPi=number('3ff921fb54442d18');
    for(const input of [neighbor(halfPi,-1),halfPi,neighbor(halfPi,1)]) assert.ok(has(op,input));
  }
  for(const op of ['asin','acos']) for(const input of [1,-1,neighbor(1,-1),neighbor(-1,1)]) assert.ok(has(op,input));
  assert.ok(has('acosh',neighbor(1,1)));assert.ok(has('acosh',Number.MAX_VALUE));
  for(const op of ['atan','asinh']) for(const input of [Number.MAX_VALUE,-Number.MAX_VALUE]) assert.ok(has(op,input));
  for(const input of [neighbor(1,-1),neighbor(-1,1)]) assert.ok(has('atanh',input));
  for(const op of ['sinh','cosh']) for(const input of [710.4758600739439,-710.4758600739439]) assert.ok(has(op,input));
  for(const args of [[1,2],[2,1],[1,1],[1,-1],[-1,-1],[-1,1],[5e-324,Number.MAX_VALUE],[-5e-324,Number.MAX_VALUE],[Number.MAX_VALUE,5e-324],[Number.MAX_VALUE,-5e-324]]) assert.ok(has('atan2',...args));
});
