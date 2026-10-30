// Read-only owner-review preparation. Current channel DATA and a local plan do
// not provide approval, registry CAS or the exclusive writer's authority.
import assert from 'node:assert/strict';
import {admitReleaseRequest} from './release-policy.mjs';
import {compareReleaseVersions, releaseVersion} from './release-version.mjs';

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

export function nativeLatestPromotionPlan(fixed, move, report, reportSha256) {
  assert.match(fixed.sha256,/^[a-f0-9]{64}$/u);assert.match(reportSha256,/^[a-f0-9]{64}$/u);
  const selected=admitReleaseRequest(fixed.manifest.request,fixed.manifest.policy);
  exact(move,['targetId','before']);
  const target=selected.request.targets.find(value=>value.id===move.targetId);
  assert(target?.ecosystem==='native'&&target.channels.includes('latest'),'Select the explicit Native Latest target');
  assert(!selected.version.prerelease,'A prerelease cannot become GitHub Latest');
  assert.equal(fixed.manifest.cohorts.find(value=>value.targetId===target.id)?.kind,'native-standalone');
  exact(report,['schemaVersion','manifestSha256','targetId','startedAt','state','requests','qualification',
    'candidate','current','inventory','publication','endedAt']);
  assert.equal(report.schemaVersion,'actql-native-latest-observation/0.1');assert.equal(report.state,'observed');
  assert.equal(report.manifestSha256,fixed.sha256);assert.equal(report.targetId,target.id);
  assert.deepEqual(report.candidate,{releaseId:report.candidate.releaseId,tag:selected.version.gitTag,
    source:selected.request.source.commit,version:selected.version.version});
  const id=report.candidate.releaseId;assert(Number.isSafeInteger(id)&&id>0);
  assert.equal(report.publication.manifestSha256,fixed.sha256);assert.equal(report.publication.targetId,target.id);
  assert.equal(report.publication.state,'published');assert.equal(report.publication.releaseId,id);
  assert(Array.isArray(report.inventory)&&report.inventory.length>0&&report.inventory.length<=1000);
  const ids=new Set();for(const value of report.inventory){
    exact(value,['releaseId','tag','draft','prerelease']);assert(Number.isSafeInteger(value.releaseId)&&value.releaseId>0&&!ids.has(value.releaseId));
    ids.add(value.releaseId);assert(typeof value.tag==='string'&&typeof value.draft==='boolean'&&typeof value.prerelease==='boolean');
  }
  assert(report.inventory.some(value=>value.releaseId===id&&value.tag===selected.version.gitTag&&!value.draft&&!value.prerelease));
  const artifacts=fixed.manifest.artifacts.filter(value=>value.targetId===target.id);
  assert.deepEqual(report.publication.observations.map(value=>value.file),artifacts.map(value=>value.file));
  assert(report.publication.observations.every(value=>value.state==='present'));
  for(const [index,value]of report.publication.observations.entries()){
    const {name,version,bytes,sha256}=artifacts[index];assert.deepEqual(value.identity,{name,version,bytes,sha256});
    assert(Number.isSafeInteger(value.assetId)&&value.assetId>0);
  }
  assert.equal(report.publication.immutableSetting?.enabled,true);
  assert.deepEqual(move.before,report.current,'Latest changed from the explicit original transition');
  let expectedVersion=null;
  if(report.current.state==='present'){
    exact(report.current,['state','releaseId','tag']);assert(Number.isSafeInteger(report.current.releaseId)&&report.current.releaseId>0);
    assert(report.inventory.some(value=>value.releaseId===report.current.releaseId&&value.tag===report.current.tag&&!value.draft&&!value.prerelease));
    assert(typeof report.current.tag==='string'&&report.current.tag.startsWith('v'));
    const previous=releaseVersion(report.current.tag.slice(1));assert.equal(previous.gitTag,report.current.tag);assert(!previous.prerelease);
    expectedVersion=previous.version;
    assert(compareReleaseVersions(selected.version.version,expectedVersion)>=0,'Native Latest cannot roll a newer full release backward');
    if(report.current.releaseId===id)assert.equal(report.current.tag,selected.version.gitTag);
  }else{
    exact(report.current,['state','releaseId']);assert.equal(report.current.state,'unassigned-or-selected');assert.equal(report.current.releaseId,id);
    const eligible=report.inventory.filter(value=>!value.draft&&!value.prerelease);
    assert.equal(eligible.length,1);assert.deepEqual(eligible[0],{releaseId:id,tag:selected.version.gitTag,draft:false,prerelease:false});
  }
  return {schemaVersion:'actql-native-latest-promotion-plan/0.1',manifestSha256:fixed.sha256,
    channelObservationSha256:reportSha256,source:selected.request.source,version:selected.version.version,
    transitions:[{targetId:target.id,name:'GitHub Release',channel:'latest',expectedVersion,toVersion:selected.version.version,
      before:structuredClone(report.current),releaseId:id,tag:selected.version.gitTag,
      action:report.current.state==='present'&&report.current.releaseId===id?'already-identical':'proposed'}],
    execution:'unavailable',pending:['Exact public Native consumer acceptance and independent owner approval of both digests',
      'One protected exclusive executor with fresh original inventory/current/asset checks'],
    qualification:'Native Latest transition DATA only; conditional initialization is not a Latest-404 absence claim, approval or CAS'};
}
