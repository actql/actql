import assert from 'node:assert/strict';
import test from 'node:test';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {RunInspector} from './dist/plan-explorer.js';
import {runObservationModel} from './run-observation.mjs';
import {observationRef, runObservationFixture, ownerObservationFixture} from './run-observation.fixture.mjs';
const render=(view=runObservationFixture(),owners=ownerObservationFixture())=>renderToStaticMarkup(
  createElement(RunInspector,{model:runObservationModel(view,owners,observationRef())}));
test('shared inspector shows separate control, Owner-local revisions and missing measurements', () => {
  const html=render();
  assert.match(html,/non_atomic/u);assert.match(html,/owner_local/u);
  assert.match(html,/Control revision<\/dt><dd>7/u);assert.match(html,/revision 3/u);
  assert.match(html,/No quantities provided; this does not mean zero/u);
  assert.match(html,/unavailable in this projection/u);assert.match(html,/unknown/u);
  assert(!html.includes('original-opaque-cursor'));assert(!html.includes('<button'));
});
test('literal strings render as text and numeric evidence is never rounded', () => {
  const view=runObservationFixture();view.run_state.run_id='<script>alert(1)</script>';
  view.quantities=[{kind:'exact',value:'9007199254740993',unit:'<img src=x>',
    scope_cid:observationRef().authorityScopeCid,basis_cid:observationRef().runDefinitionCid}];
  const html=render(view);
  assert(html.includes('9007199254740993'));assert(html.includes('&lt;img src=x&gt;'));
  assert(!html.includes('<script>'));assert(!html.includes('<img'));
});
test('terminal cancellation does not turn unknown physical stop or Result into success', () => {
  const view=runObservationFixture();view.run_state.status='cancelled';
  view.run_state.cleanup_pending=true;view.run_state.legacy_state={...ownerObservationFixture().owners[0].snapshot.value,
    status:'cancelled',control:{revision:8,cancellation_requested:true,physical_stop:'unknown'},
    result_availability:{answer:{state:'unknown',observed_at:'2026-10-15T00:00:00.000Z',reason:'verification_pending'}}};
  const html=render(view);assert.match(html,/Physical stop<\/dt><dd>unknown/u);
  assert.match(html,/Cleanup pending<\/dt><dd>true/u);assert.match(html,/verification_pending/u);
});
