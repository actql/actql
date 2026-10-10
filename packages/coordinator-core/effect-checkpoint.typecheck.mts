import {admitDispatchJson, effectCheckpointReports,
  type EffectCheckpointReport, type EffectCheckpointReply}
  from '@actql/coordinator-core';

const dispatch = admitDispatchJson('', '');
const report: EffectCheckpointReport = effectCheckpointReports.admit('', dispatch,
  {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 32});
const facts: Readonly<{reportCid: string; dispatchCid: string;
  checkpointCid: string; checkpointWire: string}> = effectCheckpointReports.facts(report);
const reply: EffectCheckpointReply = effectCheckpointReports.admitReplyJson(report, '');
if (reply.kind === 'refused') {
  const reason: 'authorization_denied' | 'scope_mismatch' | 'report_conflict' = reply.reason;
  void reason;
}
// @ts-expect-error Metadata cannot construct an opaque admitted report.
const forged: EffectCheckpointReport = {};
// @ts-expect-error A dispatch is not an admitted Checkpoint report.
effectCheckpointReports.acceptedJson(dispatch);
// @ts-expect-error A private message is not a protocol refusal reason.
effectCheckpointReports.refusedJson(report, 'private_message');
// @ts-expect-error No persistence proof or Effect approval is supplied here.
effectCheckpointReports.approve(report);
// @ts-expect-error Admitted facts are immutable.
facts.reportCid = 'other';
void [forged, reply];
