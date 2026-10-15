import test from 'node:test';import assert from 'node:assert/strict';
import {createElement} from 'react';import {renderToStaticMarkup} from 'react-dom/server';
import {CheckpointPanel} from './dist/plan-explorer.js';
import {checkpointFixture,reviewFixtureText,reviewFixtureCid} from './checkpoint-review.fixture.mjs';
const checkpoint=checkpointFixture(),review={checkpoint,artifactCid:reviewFixtureCid,byteLength:new TextEncoder().encode(reviewFixtureText).length,
 contentBase64:Buffer.from(reviewFixtureText).toString('base64')};
const render=props=>renderToStaticMarkup(createElement(CheckpointPanel,{page:{items:[checkpoint],next:'private-cursor'},review,
 pending:false,canList:true,canRead:true,onList(){},onRead(){},...props}));
test('shared review shows original subject, separate permission and no derived Run control',()=>{
 const html=render();assert(html.includes('independent of the selected Run'));assert(html.includes(checkpoint.subject.runId));
 assert(html.includes(checkpoint.reviewProjectionCid));assert(html.includes('further page exists'));assert(!html.includes('private-cursor'));
 assert(!html.includes('Approve</button>'));assert(!html.includes('Resume</button>'));assert(html.includes('does not establish current permission'));
});
test('review text is escaped and unavailable capability remains explicit',()=>{
 const html=render({canList:false,canRead:false});assert(!html.includes('<script>'));assert(html.includes('&lt;script&gt;not HTML&lt;/script&gt;'));
 assert(html.includes('Checkpoint listing is unavailable'));assert(html.includes('Review reading is unavailable'));
 assert.equal((html.match(/disabled=""/g)||[]).length,2);
});
test('empty current page is not an execution outcome or complete history',()=>{
 const html=render({page:{items:[]},review:null});assert(html.includes('No waiting Checkpoints in this authorized page'));
 assert(html.includes('not complete history'));assert(!html.includes('Original review artifact'));
});
