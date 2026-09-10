import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {eventSchemas,checkEventSchemas} from './event-schema.mjs';
import {parameterPrograms} from './parameter-schema.mjs';

test('calendar literal selectors enforce week origin and preserve field provenance syntax',()=>{
  const {calendar_bucket:b,calendar_series:s}=eventSchemas();
  for(const body of [b,s]) {
    assert.equal(body.additionalProperties,false);
    assert.deepEqual(body.allOf[0].then,{required:['week_start']});
    assert.deepEqual(body.allOf[0].else,{not:{required:['week_start']}});
    assert.deepEqual(body.properties.unit.enum,['day','week','month','quarter','year']);
    assert.equal(body.properties.timezone.type,'string');
  }
  const time=new RegExp(b.properties.time.pattern);
  for(const name of ['time','left.time','right.line\nname']) assert.ok(time.test(name));
  for(const name of ['left.__cid','left.a.b','__actql_x','']) assert.ok(!time.test(name));
  const stamp=new RegExp(s.properties.start.oneOf[0].pattern);
  assert.ok(stamp.test('0001-01-01T00:00:00.000Z'));
  assert.ok(!stamp.test('0000-01-01T00:00:00.000Z'));
});

test('sequence shares predicate grammar and never inserts implicit match limits',()=>{
  const s=eventSchemas().sequence;
  assert.deepEqual(s.required,['by','id','time','pattern','within','overlap','contiguity']);
  assert.equal(s.additionalProperties,false);
  assert.equal(s.properties.by.minItems,undefined);
  assert.equal(s.properties.by.uniqueItems,undefined);
  assert.equal(s.properties.pattern.minItems,2);
  assert.deepEqual(s.properties.pattern.items.properties.where,{$ref:'#/$defs/predicate'});
  assert.equal(s.properties.pattern.items.additionalProperties,false);
  for(const key of ['max_matches_per_key','max_output_rows']) {
    assert.equal(s.properties[key].default,undefined);
    assert.equal(s.properties[key].oneOf[0].minimum,1);
  }
});

test('as-of source syntax separates temporal keys, identity evidence and projection',()=>{
  const s=eventSchemas().asof_join;
  assert.equal(s.additionalProperties,false);
  assert.deepEqual(s.required,['with','kind','by','left_time','right_time','direction','tolerance','select']);
  assert.deepEqual(s.properties.kind.enum,['left','inner']);
  assert.deepEqual(s.properties.direction.enum,['backward','forward','nearest']);
  for(const name of ['by','right_tie_break']) {
    assert.equal(s.properties[name].minItems,undefined);
    assert.equal(s.properties[name].uniqueItems,undefined);
  }
  assert.deepEqual(s.properties.by.items.required,['left','right']);
  assert.equal(s.properties.by.items.additionalProperties,false);
  assert.equal(s.properties.select.minProperties,1);
  assert.equal(s.properties.null_key,undefined);
  assert.equal(s.properties.tolerance.oneOf[0].minimum,1);
  assert.equal(s.properties.tolerance.oneOf[0].maximum,Number.MAX_SAFE_INTEGER);
});

test('event dedupe preserves empty and repeated partition keys but requires order',()=>{
  const s=eventSchemas().dedupe_events;
  assert.equal(s.additionalProperties,false);
  assert.deepEqual(s.required,['by','order_by']);
  assert.equal(s.properties.by.minItems,undefined);
  assert.equal(s.properties.by.uniqueItems,undefined);
  assert.equal(s.properties.order_by.minItems,1);
});

test('session schema pairs relation roles and shares positive millisecond syntax',()=>{
  const s=eventSchemas().session;
  assert.deepEqual(s.required,['by','gap']);
  assert.deepEqual(s.dependentRequired,{id:['time'],time:['id']});
  assert.equal(s.additionalProperties,false);
  assert.equal(s.properties.gap.oneOf[0].minimum,1);
  assert.equal(s.properties.by.minItems,undefined);
});

test('watermark event options require literal threshold and explicit policy',()=>{
  assert.deepEqual(eventSchemas().watermark_events, {
    type:'object',additionalProperties:false,required:['watermark_ms','policy'],
    properties:{watermark_ms:{type:'number'},policy:{enum:['drop','mark']}},
  });
});
test('embedded event schemas and identity pins reject drift',()=>{
  const registry=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  checkEventSchemas(registry);
  for (const index of [0,1]) {
    for (const name of Object.keys(eventSchemas())) {
      const copy=structuredClone(registry);
      parameterPrograms(copy)[index].properties.steps.items.properties[name]={};
      assert.throws(()=>checkEventSchemas(copy));
    }
  }
});

test('interval joins require closed temporal operands and preserve repeated equality conditions',()=>{
  const s=eventSchemas().interval_join;
  assert.deepEqual(s.required,['with','kind','mode','on','left','right']);
  assert.deepEqual(s.properties.kind.enum,['inner','left','semi','anti']);
  assert.equal(s.additionalProperties,false);
  assert.equal(s.properties.on.minItems,undefined);
  assert.equal(s.properties.on.uniqueItems,undefined);
  assert.deepEqual(s.properties.on.items.required,['left','right']);
  assert.equal(s.properties.on.items.additionalProperties,false);
  assert.deepEqual(s.allOf[0].then.properties.left.required,['time']);
  assert.deepEqual(s.allOf[0].else.properties.left.required,['start','end']);
  assert.equal(s.allOf[0].then.properties.left.additionalProperties,false);
  assert.equal(s.allOf[0].else.properties.left.additionalProperties,false);
  assert.deepEqual(s.properties.right.required,['start','end']);
  assert.equal(s.properties.select.minProperties,1);
});
