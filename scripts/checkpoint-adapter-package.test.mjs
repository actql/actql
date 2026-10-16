// Actual adapter producer/public-module linkage, not a runtime/Host receipt.
import assert from 'node:assert/strict';
import {mkdir,mkdtemp,readFile} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {parse} from 'acorn';
import test from 'node:test';
import * as wire from '../packages/client-wire/index.mjs';
import {buildLocalNodeAdapters} from './build-local-node-adapters.mjs';

test('ordinary adapter producer links Checkpoint lookup through existing public wire exports',async()=>{
  const parent=resolve('_build/checkpoint-adapter-package');await mkdir(parent,{recursive:true});
  const destination=await mkdtemp(join(parent,'copy-'));
  await buildLocalNodeAdapters({destination});
  await buildLocalNodeAdapters({destination,check:true});
  const path=join(destination,'adapters/host-node/client-checkpoints.mjs');
  const source=await readFile(path,'utf8');
  const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'});
  let selected=0;
  for(const entry of ast.body){
    if(entry.type!=='ImportDeclaration'||entry.source.value!=='@actql/client-wire')continue;
    for(const specifier of entry.specifiers){
      if(specifier.type!=='ImportSpecifier')continue;
      assert.equal(typeof wire[specifier.imported.name],'function');selected++;
    }
  }
  assert.ok(selected>0,'the copied Checkpoint module must consume its public wire Owner');
  const module=await import(pathToFileURL(path));
  assert.equal(typeof module.installRemoteCheckpoints,'function');
});

test('public lookup Owner admits only the original bounded whole ID and closed page',()=>{
  for(const id of ['original','with space','東京','a\u2028\u2029b','x'.repeat(256)])
    assert.equal(wire.validCheckpointLookup({items:[]},id),true);
  for(const id of [null,undefined,true,0,'','x'.repeat(257),'original\n','original\r','x\0y'])
    assert.equal(wire.validCheckpointLookup({items:[]},id),false);
  assert.equal(wire.validCheckpointLookup({items:[],next:'cursor'},'original'),false);
  assert.equal(wire.validCheckpointLookup({items:[],foreign:true},'original'),false);
});
