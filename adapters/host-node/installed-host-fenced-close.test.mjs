import assert from 'node:assert/strict';
import {readFile, readdir} from 'node:fs/promises';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {readComputeEffectInstallation} from
  '../connectors/salesforce/test/read-compute-effect.fixture.mjs';

function journalSnapshot(directory) {
  const journal = new DatabaseSync(join(directory, 'checkpoints', 'journal',
    'checkpoint-journal.sqlite3'), {readOnly: true});
  try {
    return Object.fromEntries(['checkpoints', 'runs', 'resolutions', 'resume_intents'].map(table =>
      [table, journal.prepare(`SELECT * FROM ${table}`).all()]));
  } finally { journal.close(); }
}

async function holdingSnapshot(directory) {
  const paths = ['checkpoints/attempts', 'checkpoints/private-store/physical-holdings',
    'publication/physical-holdings'];
  return Promise.all(paths.map(async path => {
    const root = join(directory, path);
    const files = (await readdir(root)).sort();
    assert.ok(files.length > 0);
    return Promise.all(files.map(async file => [file, await readFile(join(root, file))]));
  }));
}

for (const lostCloseReply of [false, true]) {
  const name = lostCloseReply ? 'after losing the original close reply' : 'on first close';
  test(`Installed Host closes a fenced Checkpoint Journal ${name}`, async t => {
    const setup = await readComputeEffectInstallation(t);
    const id = 'fenced-approval';
    const steps = await setup.embedded(id, setup.program(), {transport: 'https'});
    assert.deepEqual(await steps('submit'), {held: true});
    const installation = join(setup.root, `embedded-${id}.json`);
    const {directory} = JSON.parse(await readFile(installation, 'utf8'));
    const ref = JSON.parse(await readFile(installation + '.ref.json', 'utf8'));
    const original = journalSnapshot(directory);
    assert.equal(original.checkpoints.length, 1);
    assert.equal(original.checkpoints[0].closure, 'open');
    assert.equal(original.runs.length, 1);
    assert.equal(original.runs[0].status, 'waiting_checkpoint');
    assert.deepEqual([original.resolutions, original.resume_intents], [[], []]);
    const holdings = await holdingSnapshot(directory);
    assert.deepEqual(await steps(lostCloseReply ? 'answer-fenced-lost-close' : 'answer-fenced'),
      {sqlite: 787, physicalCloses: 1, lostCloseReply});
    assert.deepEqual(journalSnapshot(directory), original);
    assert.deepEqual(await holdingSnapshot(directory), holdings);
    assert.deepEqual(await steps('observe-waiting'),
      {ref, ids: [original.checkpoints[0].checkpoint_cid], status: 'waiting_checkpoint'});
    assert.deepEqual(journalSnapshot(directory), original);
    assert.deepEqual(await holdingSnapshot(directory), holdings);
    assert.equal(new Set(steps.processes.map(entry => entry.pid)).size, 3);
    assert.equal(setup.queries(), 1);
    assert.equal(setup.writes().length, 0);
    const observations = await steps.ownerObservations();
    assert.equal(observations.filter(event => event.name === 'effect_computation_completed').length, 1);
  });
}
