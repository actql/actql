// Read-only owner-review preparation. Current channel DATA and a local plan do
// not provide approval, registry CAS or the exclusive writer's authority.
import assert from 'node:assert/strict';
import {admitReleaseRequest} from './release-policy.mjs';
import {compareReleaseVersions} from './release-version.mjs';

const exact = (value, keys) => {
  assert(value && typeof value === 'object' && !Array.isArray(value));
  assert.deepEqual(Object.keys(value).sort(), [...keys].sort());
};
const key = value => JSON.stringify([value.targetId, value.name, value.channel]);

export function promotionPlan(fixed, moves, report, reportSha256) {
  assert.match(fixed.sha256, /^[a-f0-9]{64}$/u);
  assert.match(reportSha256, /^[a-f0-9]{64}$/u);
  const selected = admitReleaseRequest(fixed.manifest.request, fixed.manifest.policy);
  exact(report, ['schemaVersion', 'manifestSha256', 'startedAt', 'endedAt', 'observations', 'issues', 'requests', 'qualification']);
  assert.equal(report.schemaVersion, 'actql-release-channels/0.1');
  assert.equal(report.manifestSha256, fixed.sha256, 'Channel observation belongs to another fixed candidate');
  assert(Array.isArray(report.observations));
  const expected = fixed.manifest.artifacts.filter(value => value.ecosystem === 'npm').flatMap(artifact => {
    const target = selected.request.targets.find(value => value.id === artifact.targetId);
    return target.channels.map(channel => ({targetId: target.id, name: artifact.name, channel}));
  });
  assert.equal(report.observations.length, expected.length, 'Incomplete selected channel observation');
  const seen = new Set();
  for (const observation of report.observations) {
    assert(['present', 'absent', 'unknown'].includes(observation.state));
    exact(observation, ['targetId', 'name', 'channel', 'state', ...(observation.state === 'present' ? ['version'] : [])]);
    assert(expected.some(value => key(value) === key(observation)), 'Unselected channel observation');
    assert(!seen.has(key(observation)), 'Duplicate channel observation'); seen.add(key(observation));
  }
  assert(Array.isArray(moves) && moves.length, 'Choose each channel move explicitly');
  const chosen = new Set(), transitions = [];
  for (const move of moves) {
    exact(move, ['targetId', 'name', 'channel', 'expectedVersion']);
    assert(!chosen.has(key(move)), 'Duplicate channel move'); chosen.add(key(move));
    const artifact = fixed.manifest.artifacts.find(value => value.targetId === move.targetId && value.name === move.name);
    assert(artifact && artifact.ecosystem === 'npm', 'No selected npm artifact/channel route');
    const target = selected.request.targets.find(value => value.id === move.targetId);
    assert(target.channels.includes(move.channel), 'Channel is outside the fixed release scope');
    const observation = report.observations.find(value => key(value) === key(move));
    assert(observation && observation.state !== 'unknown', 'Selected channel current value is unknown');
    const before = observation.state === 'present' ? observation.version : null;
    assert.equal(move.expectedVersion, before, 'Channel changed from the explicitly expected original value');
    assert.equal(artifact.version, selected.version.version);
    if (before !== null) assert(compareReleaseVersions(artifact.version, before) >= 0,
      'Normal promotion cannot roll a channel backward; separate owner recovery is required');
    if (move.channel === 'latest' || /^release-[0-9]+\.[0-9]+$/u.test(move.channel)) {
      assert(!selected.version.prerelease, 'A stable channel cannot relabel an RC/alpha/beta as final');
    }
    if (/^release-[0-9]+\.[0-9]+$/u.test(move.channel)) {
      assert.equal(move.channel, `release-${selected.version.line}`, 'Maintenance channel belongs to another line');
    }
    transitions.push({...move, toVersion: artifact.version, action: before === artifact.version ? 'already-identical' : 'proposed'});
  }
  return {schemaVersion: 'actql-release-promotion-plan/0.1', manifestSha256: fixed.sha256,
    channelObservationSha256: reportSha256, source: selected.request.source, version: selected.version.version,
    transitions, execution: 'unavailable',
    pending: ['Exact public-install acceptance for this fixed manifest',
      'Independent owner approval of this exact manifest and channel transition plan',
      'One exclusive protected executor with fresh channel checks; a prior read is not registry CAS'],
    qualification: 'local channel-transition DATA for owner review only; no mutation, credential, approval or lease'};
}
