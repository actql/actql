import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {checkOpenAIChatVectors,openAIChatVectors} from './openai-chat-vectors.mjs';
import {checkModelDependencySchemas} from './model-dependency-contract.mjs';

test('registered closed OpenAI payload and independent raw canonical vectors',()=>{
  const registry=JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json'));
  checkModelDependencySchemas(registry);
  assert.deepEqual(registry.artifact_schemas.openai_chat_prompt,{type:'object',additionalProperties:false,
    required:['format','instructions'],properties:{format:{const:'actql.openai_chat_prompt/0.1'},instructions:{type:'string'}}});
  checkOpenAIChatVectors();
  const {corpus}=openAIChatVectors();
  assert.equal(corpus.cases.filter(c=>c.accepted).length,2);
  assert.equal(corpus.schema_cid,'sha256:62f7715bfc032ac33d95a93b2d80aae42c76d6c83f5ba1986d51cfbe4725888d');
  assert.equal(registry.artifact_schema_cids.openai_chat_prompt,'sha256:c785e9b1efaefbf6a0c74c52bc103dd2e67eb774a9c2f860642007bce1e81a9a');
  assert.equal(registry.artifact_schema_cids.model_prompt,'sha256:ce2b3c73852f55d01ccc9ed730c21ad6f3cb842fc6307e2dfa272fc2c3468204');
});
