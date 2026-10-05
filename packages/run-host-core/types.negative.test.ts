import type {DeliveryContractView, PublicationContract,
  PublicationRequestContract, PublicationAttemptContract,
  PublicationRecordContract, PublicIndexEntryContract,
  ResultDeliveryControl, PreparedProgram, ValuesCompilation,
  RunAdmission, RunDefinition, CheckEnvironment, RetainedTaskInputEdge,
  TaskCompilation, RetainedInputProducer} from '@actql/run-host-core';
import {issueUnpublishedRunStateWire, issuePublicationAttempt,
  issuePublicationRecord, validatePublicationRecordTransition,
  issueSourceFreeRunMaterials, prepareRetainedTaskInputEdge,
  retainedTaskInputEdgeFacts, prepareRetainedInputProducer,
  retainedInputProducerAvailable, retainedInputProducerFacts} from
  '@actql/run-host-core';

declare const control: ResultDeliveryControl;
declare const manifest: DeliveryContractView<'result_manifest'>;
declare const retention: DeliveryContractView<'result_retention_policy'>;
declare const publication: PublicationContract;
declare const publicationRequest: PublicationRequestContract;
declare const publicationAttempt: PublicationAttemptContract;
declare const publicationRecord: PublicationRecordContract;
declare const publicIndex: PublicIndexEntryContract;
declare const publicationLimits: Parameters<typeof issuePublicationAttempt>[3];
declare const runPublicationDefinition: PublicationContract;
declare const prepared: PreparedProgram;
declare const compilation: ValuesCompilation;
declare const admission: RunAdmission;
declare const definition: RunDefinition;
declare const environment: CheckEnvironment;
declare const taskCompilation: TaskCompilation;
declare const edge: RetainedTaskInputEdge;
declare const producer: RetainedInputProducer;
prepareRetainedInputProducer(edge, () => ({authority: 'scope', durableRecordWire: '{}'}));
retainedInputProducerAvailable(producer);
retainedInputProducerFacts(producer);
// @ts-expect-error Saved bytes alone cannot install a trusted current owner port.
prepareRetainedInputProducer(edge, {authority: 'scope', durableRecordWire: '{}'});
// @ts-expect-error An edge has no completed producer custody.
retainedInputProducerAvailable(edge);
// @ts-expect-error A canonical evidence projection is not the owned producer.
retainedInputProducerAvailable(retainedInputProducerFacts(producer));
retainedTaskInputEdgeFacts(edge);
prepareRetainedTaskInputEdge(prepared, taskCompilation, admission,
  definition, 1, 0);
// @ts-expect-error A copied projection cannot replace the owned checked edge.
retainedTaskInputEdgeFacts(retainedTaskInputEdgeFacts(edge));
// @ts-expect-error A compilation is not a checked input edge.
retainedTaskInputEdgeFacts(taskCompilation);
// @ts-expect-error Values compilation cannot supply dependent task topology.
prepareRetainedTaskInputEdge(prepared, compilation, admission, definition, 1, 0);
issueSourceFreeRunMaterials(prepared, compilation, admission, definition,
  {document: '{}', format: 'json', environment, environmentWire: '{}'});
// @ts-expect-error Raw received JSON cannot replace the admitted Run owner.
issueSourceFreeRunMaterials(prepared, compilation, admission, '{}',
  {document: '{}', format: 'json', environment, environmentWire: '{}'});
issueSourceFreeRunMaterials(prepared, compilation, admission, definition,
  // @ts-expect-error The currently admitted materials wire requires JSON.
  {document: '{}', format: 'yaml', environment, environmentWire: '{}'});

control.resultReadDefinitionCid(manifest, 'answer');
control.resultRetentionClockContractCid(retention);
issuePublicationAttempt(publicationRequest, runPublicationDefinition, {
  attemptId: 'a', fenceCid: 'f', startedAt: '2026-09-27T00:00:00.000Z',
}, publicationLimits);
validatePublicationRecordTransition(undefined, publicationRecord, false);
issuePublicationRecord(publicationAttempt, publicationRecord, {
  state: 'succeeded', observedAt: '2026-09-27T00:00:00.000Z',
  publicIndexEntry: publicIndex, cleanupOwnerCids: [],
  uncommittedConfirmed: false,
}, publicationLimits);
issueUnpublishedRunStateWire(prepared, compilation, admission, definition,
  '2026-09-27T00:00:00.000Z', {
    dispatchReserved: true, preDispatchFailureConfirmed: false,
  });

// @ts-expect-error A same-shaped object cannot replace an owned view.
control.resultReadDefinitionCid({name: 'result_manifest',
  identityField: 'result_manifest_cid', identity: 'sha256:x', wire: '{}'},
'answer');
// @ts-expect-error An admitted retention policy is not a Result manifest.
control.resultReadDefinitionCid(retention, 'answer');
// @ts-expect-error A publication handle is not a delivery view.
control.resultReadDefinitionCid(publication, 'answer');
// @ts-expect-error A record is not a publication request.
issuePublicationAttempt(publicationRecord, runPublicationDefinition, {
  attemptId: 'a', fenceCid: 'f', startedAt: '2026-09-27T00:00:00.000Z',
}, publicationLimits);
// @ts-expect-error An attempt is not a predecessor record.
validatePublicationRecordTransition(publicationAttempt, publicationRecord,
  false);
// @ts-expect-error A same-shaped object cannot forge an owner-issued request.
issuePublicationAttempt({cid: 'sha256:x', wire: '{}', token: {}},
  runPublicationDefinition, {
    attemptId: 'a', fenceCid: 'f', startedAt: '2026-09-27T00:00:00.000Z',
  }, publicationLimits);
issueUnpublishedRunStateWire(prepared, compilation, admission, definition,
  // @ts-expect-error Run state observations must name each physical fact.
  '2026-09-27T00:00:00.000Z', true);
