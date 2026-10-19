import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const read = path => JSON.parse(readFileSync(path,'utf8'));
const canonical = value => Array.isArray(value) ? '['+value.map(canonical).join(',')+']'
  : value !== null && typeof value === 'object' ? '{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+canonical(value[k])).join(',')+'}'
    : JSON.stringify(value);
const hash = text => 'sha256:'+createHash('sha256').update(text).digest('hex');
const cid = value => hash(canonical(value));
const before = read('scripts/fixtures/date-add-source/predecessor.json');
const beforeQueryTime = Object.fromEntries(read('scripts/fixtures/query-time-source/predecessor.json').contracts.map(item=>[item.id,item.body]));

test('DATE_ADD retains complete prior scalar/AoA/grammar bodies and only the adopted exact-duration law changes',()=>{
  assert.equal(cid(before.scalar),'sha256:65e19916636e8d7dcf3bc7a1f8640762ef2dee048105c7b869878bd0fdf4d8fe');
  assert.equal(cid(before.aoa),'sha256:899be6a80ef655f4460e4a0414ec2ef861110b63c19f257de7a5579efa09470c');
  assert.deepEqual(before.grammar,read('scripts/fixtures/date-trunc-source/identities.json').after);
  const current = beforeQueryTime.scalar_law_manifest;
  const {date_add: rule,...oldTime} = current.time;
  assert.deepEqual({...current,time:oldTime},before.scalar);
  assert.deepEqual(rule,{
    amount:'evaluate_original_Number_expression_then_interpret_resulting_finite_binary64_bits_exactly',
    duration:'exact_evaluated_Number_times_declared_fixed_unit_no_intermediate_binary64_unit_product_or_decimal_spelling_reinterpretation',
    representability:'nonintegral_nanosecond_result_fails_ArithmeticFailure_without_rounding_or_truncation',
    range:'exact_signed_carry_preserves_original_nanoseconds_calendar_overflow_fails',
    date:'integer_amount_and_d_only',
    examples:{aligned_seconds_0_125:'success',aligned_milliseconds_0_5:'success',binary64_seconds_0_1:'ArithmeticFailure',binary64_seconds_1e_minus_9:'ArithmeticFailure'},
  });
  assert.notEqual(cid(current),cid(before.scalar));
  const aoa=beforeQueryTime.aoa_contract;
  assert.equal(aoa.rela_scalar_law_manifest_cid,cid(current));
  assert.deepEqual({...aoa,rela_scalar_law_manifest_cid:before.aoa.rela_scalar_law_manifest_cid},before.aoa);
  assert.equal(current.time.timestamp_date_diff,before.scalar.time.timestamp_date_diff);
  assert.equal(current.time.operational_clocks,before.scalar.time.operational_clocks);
});

test('DATE_ADD independent rational Number vectors distinguish exact dyadics from decimal-looking durations',()=>{
  const units={ms:1000000n,s:1000000000n,m:60000000000n,h:3600000000000n,d:86400000000000n};
  for(const row of read('scripts/fixtures/date-add-source/durations.json')){
    const data=new DataView(new ArrayBuffer(8));data.setFloat64(0,row.amount,false);
    const bits=data.getBigUint64(0,false);
    assert.equal(bits.toString(16).padStart(16,'0'),row.bits);
    const exponent=Number((bits>>52n)&2047n);
    const significand=(bits&((1n<<52n)-1n))|(exponent===0?0n:1n<<52n);
    const power=exponent===0?-1074:exponent-1075;
    let numerator=significand*units[row.unit]*(bits>>63n?-1n:1n);
    let denominator=1n;
    if(power<0)denominator<<=BigInt(-power);else numerator<<=BigInt(power);
    const gcd=(a,b)=>b===0n?a:gcd(b,a%b);
    const common=gcd(numerator<0n?-numerator:numerator,denominator);
    numerator/=common;denominator/=common;
    assert.equal(numerator.toString(),row.exactNanosecondsNumerator);
    assert.equal(denominator.toString(),row.exactNanosecondsDenominator);
    assert.equal(denominator===1n,row.representable);
  }
});

test('DATE_ADD source rule has a genuine new grammar identity without changing existing expression/Program shapes',()=>{
  const current=read('scripts/fixtures/explicit-decimal-source/predecessor.json');
  for(const grammar of [before.grammar,current]){
    const {grammar_manifest_cid,...body}=grammar;assert.equal(cid(body),grammar_manifest_cid);
  }
  // This complete DATE_ADD predecessor retains its original query-rule pin.
  assert.deepEqual({...current,grammar_manifest_cid:before.grammar.grammar_manifest_cid,query_text_rules_sha256:before.grammar.query_text_rules_sha256},before.grammar);
  const source={date_add:[{field:'clock'},{$param:'amount'},{literal:'s'}]};
  assert.equal(canonical(source),'{"date_add":[{"field":"clock"},{"$param":"amount"},{"literal":"s"}]}');
  assert.equal(current.expression_contract_cid,before.grammar.expression_contract_cid);
  assert.equal(current.source_grammar_cid,before.grammar.source_grammar_cid);
});
