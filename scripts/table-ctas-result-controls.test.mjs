import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {dirname, relative, resolve} from 'node:path';
import test from 'node:test';
import {buildSync} from 'esbuild';
import {ctasResultControl, ctasRetainedResult} from '../adapters/host-node/fixtures/table-ctas-result-control.mjs';
import {tablePublicTestGroups, tablePublicFixturePaths} from './table-public-acceptance-cases.mjs';

test('retained CTAS independent machine control keeps the pre-filter port public and writes the filtered port', () => {
  const source = ctasResultControl('json', {targetRef: 'connector://table/catalog', mappingRef: 'mapping:table.catalog.v1'});
  const program = JSON.parse(source.document), stage = program.stages[0];
  assert.deepEqual(stage.steps[0].values, {schema: {id: {type:'number',nullable:false},
    tag: {type:'string',nullable:true}}, rows: [{id:1,tag:null}]});
  assert.deepEqual(stage.steps[1], {from:'original',filter:'id = 2',as:'filtered'});
  assert.deepEqual(stage.results.before_write, {from:'original',fields:['id','tag']});
  assert.deepEqual(stage.effects.save.store.from, {result:'written'});
  assert.deepEqual(stage.results.written, {from:'filtered',fields:['id','tag']});
  assert.deepEqual(program.results, {before_write:{from:{stage:'main',result:'before_write'}}});
  assert.deepEqual(ctasRetainedResult.rows, [{id:1,tag:null}]);
  assert.deepEqual(ctasRetainedResult.columns.map(value=>value.name), ['id','tag']);
});

test('SQL and AQL retained CTAS use the adopted whole Compute wrapper and unchanged predicate', () => {
  const expected = 'CREATE TABLE analytics.report AS (SELECT 1 AS id, CAST(NULL AS STRING) AS tag' +
    ' |> RESULT before_write |> WHERE id = 2)';
  for (const format of ['sql','aql']) assert.deepEqual(ctasResultControl(format, {}), {format,document:expected});
  assert.throws(()=>ctasResultControl('other', {}));
});

test('closed CTAS physical selection retains the original twenty cases and requires six new controls', () => {
  const all = tablePublicTestGroups();
  assert.deepEqual(all.slice(0,-1).map(value=>value.expected), [4,7,2,2,2,3]);
  assert.equal(all.slice(0,-1).reduce((sum,value)=>sum+value.expected,0),20);
  assert.equal(all.reduce((sum,value)=>sum+value.expected,0),26);
  const focused = tablePublicTestGroups('ctas');
  assert.deepEqual(focused.map(value=>value.expected),[4,6]);
  const expectedNames=['Local','HTTPS'].flatMap(transport=>['json','sql','aql'].map(format=>
    `Table retained Result before filtered CTAS through ${transport} (${format})`));
  for(const name of expectedNames) assert(new RegExp(focused[1].pattern,'u').test(name));
  assert(!new RegExp(focused[1].pattern,'u').test('Table retained Result before filtered CTAS through Local (other)'));
  assert.throws(()=>tablePublicTestGroups('unknown'));
  assert.throws(()=>tablePublicTestGroups(''));
});

test('packed CTAS fixture inventory covers actual relative modules and literal file readers', () => {
  const graph = buildSync({entryPoints: ['adapters/host-node/table-public-commit.test.mjs',
    'adapters/host-node/fixtures/table-text-restart.mjs'], bundle:true, packages:'external',
    platform:'node', format:'esm', target:'node22', metafile:true, write:false,
    outdir:'unused-table-closure-output', logLevel:'silent'});
  const required = new Set(Object.keys(graph.metafile.inputs));
  for (const path of required) {
    const source=readFileSync(path,'utf8');
    for (const match of source.matchAll(/readFile(?:Sync)?\(\s*new URL\(\s*['"]([^'"]+)['"],\s*import\.meta\.url\)/gu)) {
      required.add(relative(process.cwd(),resolve(dirname(path),match[1])));
    }
  }
  const missing = paths => [...required].filter(path=>!paths.includes(path));
  assert.deepEqual(missing(tablePublicFixturePaths),[]);
  assert.deepEqual(missing(tablePublicFixturePaths.filter(path=>!path.endsWith('/table-ctas-result-control.mjs'))),
    ['adapters/host-node/fixtures/table-ctas-result-control.mjs']);
  assert.deepEqual(missing(tablePublicFixturePaths.filter(path=>!path.endsWith('/actql-protocol-schemas.json'))),
    ['spec/contracts/actql-protocol-schemas.json']);
});
