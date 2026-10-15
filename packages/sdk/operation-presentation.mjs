import {freezeInput} from './internal/data.mjs';
// Operation wording is separate from retained observations and wire identity.
import {getCheckPresentationInfo} from './check-presentation.mjs';

const summaries = Object.freeze({
  'observation.observation_unavailable': 'Runの観測を完了できませんでした。この失敗は実行・Effect・公開・解放の結果を確定しません。',
  'observation.unknown_state': 'このSDKではRun応答の状態を解釈できません。',
  'observation.contract_mismatch': 'Run応答がこのSDKの登録済み状態契約と一致しません。',
  'observation.malformed_response': 'Run応答が登録済み状態契約に違反しています。',
  'observation.stale_observation': 'Run応答のcontrol revisionが古いか、同じrevisionで観測済みのcontrol事実と矛盾しています。',
  'submission.acceptance_unknown': '送信の受理を確認できません。処理は既に始まっている可能性があります。',
  'submission.not_accepted': 'Hostは受理前の拒否を耐久記録しました。このidentityは消費済みで、Run参照は返されていません。',
  'submission.preparation_failed': 'Hostは提出を受理した後、準備に失敗しました。Run参照は返されておらず、受理前の拒否ではありません。',
  'submission.preparing': 'Hostは提出を受理し、準備はまだ完了していません。Run参照は返されていません。',
  'submission.history_unresolvable': 'Hostは元の提出結果を確定できません。処理は既に始まっている可能性があります。',
  'submission.lookup_unavailable': '提出の照会を完了できませんでした。受理・実行は未確定です。',
  'submission.lookup_uninterpretable': 'このSDKでは提出の照会応答を解釈できません。受理・実行は未確定です。',
  'submission.not_sent': 'このSDKは今回の提出を送信していません。これはOwnerによる拒否ではなく、元のidentityの結果も確定しません。',
  'submission.refused.authorization': 'Hostは現在の認可により今回の提出呼出しを拒否しました。今回の呼出しは提出をcommitせず、操作identityも消費していません。',
  'submission.refused.admission_capacity': 'Hostは受付容量が不足しているため今回の提出呼出しを拒否しました。今回の呼出しは提出をcommitせず、操作identityも消費していません。',
  'submission.refused.epoch_expired': 'Hostは提出したepochが期限切れのため今回の提出呼出しを拒否しました。元の提出結果は確定しません。',
  'submission.refused.epoch_not_yet_valid': 'Hostは提出したepochがまだ有効でないため今回の提出呼出しを拒否しました。元の提出結果は確定しません。',
  'submission.conflict.intent': 'Hostは元の提出identityに対する意図の競合を報告しています。',
  'submission.conflict.restart_decision': 'Hostは元の提出identityに対する再開始の判断の競合を報告しています。',
  'request.lookup_unresolved': 'この照会だけでは送信が受理されたか判断できません。',
  'request.lookup_uninterpretable': 'このSDKでは要求の照会応答を解釈できません。受理・実行は未確定です。',
  'request.lookup_unavailable': 'Hostから要求の照会結果を取得できませんでした。受理は未確定です。',
  'request.run_reference_received': 'Hostは検証済みのRun参照を返しました。実行の進行はRunの現在状態で確認してください。',
  'request.request_held.waiting_checkpoint': 'Hostは要求を耐久保持し、準備はCheckpointを待っています。Run参照は返されていません。',
  'request.request_held.resuming': 'Hostは保留要求の準備が再開中と報告しています。Run参照は返されていません。',
  'request.request_held.ended': 'Hostは保留要求の準備が終了したと報告しています。Run参照は返されていません。',
  'submission.run_reference_received': 'Hostは検証済みのRun参照を返しました。実行の進行はRunの現在状態で確認してください。',
  'requestCancellation.accepted': 'Hostはこの要求の取消しを記録しました。この応答は物理停止・資源解放を確定しません。',
  'requestCancellation.already_requested': 'Hostはこの要求について記録済みの取消しを報告しています。この応答は物理停止・資源解放を確定しません。',
  'requestCancellation.already_terminal': 'Hostはこの要求が既に終端状態にあると報告しています。この応答は実行結果・物理停止・資源解放を確定しません。',
  'requestCancellation.outcome_unknown': 'この要求取消しについて利用可能な観測が返されませんでした。この観測は耐久記録・物理停止・資源解放を確定しません。',
  'cancellation.accepted': 'HostはRunの取消し要求を記録しました。物理停止・Effect・解放はRunの現在状態で確認してください。',
  'cancellation.already_requested': 'Hostは既存のRun取消し要求を報告しました。物理停止・Effect・解放はRunの現在状態で確認してください。',
  'cancellation.already_terminal': 'Hostは取消しについてRunが既に終端状態にあると報告しました。Effect・解放の詳細はRunの現在状態で確認してください。',
  'cancellation.outcome_unknown': 'Run取消しの結果を確認できません。要求は記録されている可能性があります。',
  'cancellation.refused.authorization': 'Hostは現在の認可により今回の取消し呼出しを拒否しました。今回の呼出しは取消しをcommitせず、操作identityも消費していません。',
  'cancellation.refused.admission_capacity': 'Hostは受付容量が不足しているため今回の取消し呼出しを拒否しました。今回の呼出しは取消しをcommitせず、操作identityも消費していません。',
  'cancellation.conflict.intent': 'Hostは元の取消しidentityに対する意図の競合を報告しています。',
  'cancellation.conflict.control_revision': 'Hostは今回の取消し呼出しで提出したcontrol revisionとの競合を報告しています。',
  'effect.effect_outcome_unknown': '外部Effectの結果は未確定です。計算の停止はEffectの結果や資源解放を示しません。',
  'delivery.lookup_unresolved': 'この照会ではDeliveryAttemptが見つかりませんでした。読み取りが開始されたかは未確定です。',
  'delivery.lookup_unavailable': 'DeliveryAttemptの照会を完了できませんでした。読み取り開始・配信は未確定です。',
  'delivery.lookup_uninterpretable': 'このSDKではDeliveryAttemptの照会応答を解釈できません。読み取り開始・配信は未確定です。',
  'delivery.attempt_recorded': 'HostはこのDeliveryAttemptを記録しています。配信結果はまだ取得できません。',
  'delivery.delivery_streaming': 'HostはこのDeliveryが配信中と報告しています。完了は確認できていません。',
  'delivery.host_delivery_succeeded': 'HostはこのDeliveryを確認し、解放receiptを発行しました。',
  'delivery.delivery_failed': 'HostはこのDeliveryの失敗を報告しています。Runの失敗を意味しません。',
  'delivery.delivery_cancelled': 'HostはこのDeliveryの取消しを報告しています。Runの取消しを意味しません。',
  'read.read_open_unknown': '読み取りの開始を確認できません。DeliveryAttemptは既に記録されている可能性があります。',
});
const readHint = 'この読み取り参照を保持してください。先頭から新しく読み取るか判断する前に、元の参照で状態を確認してください。';

export function getOperationPresentationInfo(options) {
  const {locale} = getCheckPresentationInfo(options);
  return Object.freeze({locale, translationRevision: `2026-10-09.operations.${locale}.13`});
}

export function localizeOperation(explanation, domain, options) {
  if (explanation === undefined) return undefined;
  if (getOperationPresentationInfo(options).locale !== 'ja') return explanation;
  let key = domain + '.' + (domain === 'observation' ? explanation.problem : explanation.observation);
  if ((domain === 'request' || domain === 'submission') && explanation.observation === 'request_held') {
    key = 'request.request_held.' + explanation.preparationState;
  }
  if ((domain === 'submission' || domain === 'cancellation') && ['refused', 'conflict'].includes(explanation.observation)) {
    key += '.' + explanation.reason;
  }
  let summary, hint;
  if (domain === 'request' || domain === 'submission' && explanation.observation === 'request_held') {
    hint = '元の要求参照を保持し、認可された照会を使ってください。この観測は再送信・実行・Checkpointへの回答・資源解放を許可しません。';
  }
  if (domain === 'submission' && explanation.hint !== undefined && explanation.observation !== 'request_held') {
    hint = '元の提出参照を保持し、認可された照会を使ってください。この観測は再送信・実行・資源解放を許可しません。';
  }
  if (domain === 'submission' && ['refused', 'conflict'].includes(explanation.observation)) hint = '元の提出参照を保持し、現在の認可で照会してください。今回の呼出し結果は別の呼出しの受理を確定せず、再提出・変更した入力・新しい再開始の判断を許可しません。';
  if (domain === 'requestCancellation') hint = '元の要求参照を保持し、現在の認可で要求または示されたRunを確認してください。この観測は再送信・資源解放・外部Effectの再実行を許可しません。';
  if (domain === 'cancellation' && ['refused', 'conflict'].includes(explanation.observation)) hint = '元の取消し参照を保持し、現在の認可で照会してください。今回の呼出し結果は別の呼出しの結果を確定せず、再送信を許可せず、物理停止・外部Effect・資源解放を確認しません。';
  if (domain === 'delivery') hint = '元の読み取り参照を保持してください。この観測はアプリケーションでの受領・保存を確認せず、再読取やComputeの再実行も許可しません。';
  if (domain === 'read') hint = readHint;
  if (domain === 'observation') hint = '現在の認可で元のRun状態を確認してください。この観測は実行・Effect・公開・解放の結果を確定せず、書き込みの再試行を許可しません。';
  if (key === 'read.read_incomplete') {
    summary = `この読み取りは${explanation.rowsYielded}行を返した後で停止しました。`;
    hint = readHint;
  } else if (key === 'read.cleanup_unknown') {
    summary = `${explanation.rowsYielded}行を返した後のreader cleanupを確認できません。`;
    hint = readHint;
  } else if (Object.hasOwn(summaries, key)) summary = summaries[key];
  // Missing translations retain the same safe English observation.
  if (summary === undefined) return explanation;
  return Object.freeze({...explanation, summary, ...(hint === undefined ? {} : {hint})});
}

const ownerHistoryAdvice = {
  not_provided: ['This Owner provides a current view without transition history.',
    'Earlier transitions are not established by the current snapshot.'],
  retention_expired: ['The Owner reports that the requested history is outside retained history.',
    'A current snapshot does not fill this history gap or establish earlier outcomes.'],
  history_unrecoverable: ['The Owner could not recover the requested history.',
    'Keep the original Run reference; missing history establishes no absent execution or Effect.'],
  cursor_mismatch: ['The cursor does not match this Owner observation scope or stream.',
    'Use only a cursor returned for the original Run and Owner under current authorization.'],
  cursor_expired: ['The supplied observation cursor has expired.',
    'Cursor expiry does not establish history retention expiry. Obtain a fresh observation explicitly.'],
  limit_exceeded: ['The observation budget could not cover the requested history.',
    'Review the observation limits. This partial observation does not establish complete history.'],
  acquisition_failed: ['The requested history could not be acquired.',
    'Keep the original Run reference. Acquisition failure establishes no earlier outcome.'],
  page: ['The Owner returned a page of recorded transitions in Owner-local order.',
    'The page is not a global event order or an atomic view of other Owners. A returned cursor grants no execution or retry permission.'],
};

const ownerUnavailableAdvice = {
  acquisition_failed: ['The Owner observations could not be acquired.',
    'The acquisition failure establishes no stream identity, absence or earlier outcome.'],
  limit_exceeded: ['The observation budget could not cover this Owner.',
    'Other available views do not establish a complete observation of this Owner.'],
  history_unrecoverable: ['The Owner observations could not be recovered.',
    'Missing observations establish no stream identity, absence or earlier outcome.'],
  cursor_mismatch: ['The supplied cursor could not be matched to this Owner observation.',
    'A mismatch establishes no stream identity, absence or earlier outcome.'],
};

const ownerSnapshotAdvice = {
  acquisition_failed: ['The current Owner snapshot could not be acquired.',
    'Available history does not substitute for a current snapshot.'],
  limit_exceeded: ['The current Owner snapshot exceeded the observation budget.',
    'Available history does not establish a complete current view.'],
};

const advice = (facts, messages) => ({...facts, summary: messages[0], hint: messages[1]});

export const projectOwnerObservations = (answer, input, lookupContext) => {
  const owners = answer.owners.map(view => {
    if (view.kind === 'unavailable') return advice(view, view.problem === undefined ? [
      'This Owner observation is unavailable.',
      'Unavailability establishes no stream identity, absence, execution or release outcome.',
    ] : ownerUnavailableAdvice[view.problem.kind]);
    const explained = {...view, history: advice(view.history, ownerHistoryAdvice[view.history.kind])};
    if (view.snapshotProblem !== undefined) {
      explained.snapshotProblem = advice(view.snapshotProblem, ownerSnapshotAdvice[view.snapshotProblem.kind]);
    }
    return explained;
  });
  return freezeInput({
    ...answer, owners, observation: 'owner_views',
    requested: {cursors: input.cursors, maxEntries: input.maxEntries, maxWireBytes: input.maxWireBytes},
    lookupContext,
    summary: 'These Owner observations were acquired independently and are ordered within each Owner only.',
    hint: 'Keep the original Run reference and distinguish snapshots from history gaps. Reobserve explicitly under current authorization; this observation grants no execution, resend, cancellation or release permission.',
  });
};

export const projectCancellationExplanation = (result, context, observation, revision) => {
  const summaries = {
    accepted: 'The Host recorded a Run cancellation request. Refresh Run state for physical stop, Effects and release.',
    already_requested: 'The Host reports an existing Run cancellation request. Refresh Run state for physical stop, Effects and release.',
    already_terminal: 'The Host reports the Run is already terminal for cancellation. Refresh Run state for Effect and release details.',
    outcome_unknown: 'The Run cancellation outcome is unknown. The request may have been recorded.',
  };
  return freezeInput({observation,
    ...(revision === undefined ? {} : {revision}), summary: summaries[observation],
    next: observation === 'outcome_unknown'
      ? {operation: 'lookupCancellation', cancelRef: context.cancelRef}
      : {operation: 'status', ref: context.ref}});
};

export const projectCancellationAttemptExplanation = (result, context) => {
  // The response has already been captured, detached and twice admitted against
  // this invocation. A refusal is not a fact about another invocation's commit.
  if (result.kind !== 'refused' && result.kind !== 'conflict') {
    return projectCancellationExplanation(result, context,
      result.cancellation.kind, result.cancellation.revision);
  }
  const summaries = result.kind === 'refused' ? {
    authorization: 'The Host refused this cancellation invocation under current authorization. This invocation committed no cancellation and consumed no operation identity.',
    admission_capacity: 'The Host refused this cancellation invocation because admission capacity was unavailable. This invocation committed no cancellation and consumed no operation identity.',
  } : {
    intent: 'The Host reports a conflicting intent for this original cancellation identity.',
    control_revision: 'The Host reports a conflict with the submitted control revision for this cancellation invocation.',
  };
  return freezeInput({
    observation: result.kind, reason: result.reason,
    attemptRef: context.attemptRef, cancelRef: context.cancelRef,
    ...(result.kind === 'refused' ? {guarantee: result.guarantee} : {}),
    summary: summaries[result.reason],
    hint: 'Keep the original cancellation reference and use a currently authorized lookup. This invocation outcome does not establish another invocation\'s outcome, grant permission to resend, or confirm physical stop, external Effects or resource release.',
    next: {operation: 'lookupCancellation', cancelRef: context.cancelRef},
  });
};

export const projectDeliveryExplanation = (answer, next) => {
  const record = answer.kind === 'found' ? answer.record : null;
  const observation = answer.kind === 'not_found' ? 'lookup_unresolved' :
    record === null ? 'attempt_recorded' : {
      streaming: 'delivery_streaming', succeeded: 'host_delivery_succeeded',
      failed: 'delivery_failed', cancelled: 'delivery_cancelled',
    }[record.state];
  const summaries = {
    lookup_unresolved: 'This lookup found no DeliveryAttempt; whether the read opened remains unresolved.',
    attempt_recorded: 'The Host recorded this DeliveryAttempt; no delivery outcome is available yet.',
    delivery_streaming: 'The Host reports that this Delivery is streaming; completion is not confirmed.',
    host_delivery_succeeded: 'The Host confirmed this Delivery and issued its release receipt.',
    delivery_failed: 'The Host reports that this Delivery failed; this does not fail the Run.',
    delivery_cancelled: 'The Host reports that this Delivery was cancelled; this does not cancel the Run.',
  };
  return freezeInput({observation, summary: summaries[observation],
    hint: 'Keep this original read reference. This observation does not confirm application receipt or persistence, and grants no permission to reopen or rerun Compute.',
    ...(record === null ? {} : {
      recordSequence: record.sequence, hostConfirmedByteCount: record.confirmed_byte_count,
      exposure: record.exposure,
      ...(record.possible_unconfirmed_max_bytes === undefined ? {} :
        {possibleUnconfirmedMaxBytes: record.possible_unconfirmed_max_bytes}),
      ...(record.cleanup_owner_cids.length ? {cleanup: 'unresolved'} : {}),
    }),
    ...(record?.state === 'succeeded' ? {
      hostReleaseReceiptCid: answer.hostReleaseReceipt.result_delivery_receipt_cid,
      deliveredSha256: answer.hostReleaseReceipt.delivered_sha256,
    } : {}),
    next,
  });
};

export const projectReadExplanation = (result, context, rowsYielded, observation, cleanupUnknown = false) => {
  const quantity = `${rowsYielded} ${rowsYielded === 1 ? 'row' : 'rows'}`;
  return freezeInput({observation,
    ...(cleanupUnknown ? {cleanup: 'unknown'} : {}),
    attemptId: context.attemptId, rowsYielded,
    summary: observation === 'read_open_unknown'
      ? 'Opening this read could not be confirmed. The DeliveryAttempt may already have been recorded.'
      : observation === 'cleanup_unknown'
      ? `Reader cleanup could not be confirmed after returning ${quantity}.`
      : `This read stopped after returning ${quantity}.`,
    hint: 'Keep this read reference. Look it up before deciding whether to open a new read from the beginning.',
    next: {operation: 'deliveryAttempt', ref: context.ref,
      resultName: context.resultName, attemptId: context.attemptId,
      lookupContext: context.lookupContext},
  });
};

export const submissionLookupExplanation = (observation, input) => freezeInput({
  observation,
  summary: 'Submission acceptance is unknown. Work may already have started.',
  next: {operation: input.submissionRef === undefined ? 'lookupRequest' : 'lookupSubmission',
    ...(input.submissionRef === undefined ? {requestId: input.requestId} : {submissionRef: input.submissionRef}),
    lookupContext: input.lookupContext},
});

const submissionObservationHint = 'Keep the original submission reference and use an authorized lookup. This observation grants no permission to resubmit, execute or release resources.';

const submissionTarget = context => ({operation: 'lookupSubmission',
  submissionRef: context.submissionRef, lookupContext: context.lookupContext});

const requestObservationHint = 'Keep the original request reference and use an authorized lookup. This observation grants no permission to resubmit, execute, answer a Checkpoint or release resources.';

const heldRequestExplanation = (answer, context) => freezeInput({
  observation: 'request_held', preparationState: answer.state,
  prepareAttemptId: answer.prepareAttemptId, durability: answer.durability,
  summary: {
    waiting_checkpoint: 'The Host durably holds this request while preparation waits for a Checkpoint. No Run reference was returned.',
    resuming: 'The Host reports that preparation of this held request is resuming. No Run reference was returned.',
    ended: 'The Host reports that preparation of this held request ended. No Run reference was returned.',
  }[answer.state], hint: requestObservationHint,
  next: context.submissionRef === undefined
    ? {operation: 'lookupRequest', requestId: context.requestId, lookupContext: context.lookupContext}
    : {operation: 'lookupSubmission', submissionRef: context.submissionRef, lookupContext: context.lookupContext},
});

const requestCancellationHint = 'Keep the original request reference and inspect the current request or named Run under current authorization. This observation grants no permission to resubmit, release resources or repeat an external Effect.';

export const projectSubmissionAttemptExplanation = (result, attempt, snapshot) => {
  // This admitted invocation fact is separate from the original durable
  // receipt. Keep only the submitted reference, never a conflicting old intent.
  const summaries = attempt.kind === 'refused' ? {
    authorization: 'The Host refused this submission invocation under current authorization. This invocation committed no submission and consumed no operation identity.',
    admission_capacity: 'The Host refused this submission invocation because admission capacity was unavailable. This invocation committed no submission and consumed no operation identity.',
    epoch_expired: 'The Host refused this submission invocation because its submitted epoch has expired. This does not establish the original submission outcome.',
    epoch_not_yet_valid: 'The Host refused this submission invocation because its submitted epoch is not yet valid. This does not establish the original submission outcome.',
  } : {
    intent: 'The Host reports a conflicting intent for this original submission identity.',
    restart_decision: 'The Host reports a conflicting restart decision for this original submission identity.',
  };
  return freezeInput({
    observation: attempt.kind, reason: attempt.reason,
    attemptRef: snapshot.attemptRef, submissionRef: snapshot.submissionRef,
    ...(attempt.kind === 'refused' ? {guarantee: attempt.guarantee} : {}),
    summary: summaries[attempt.reason],
    hint: 'Keep the original submission reference and use a currently authorized lookup. This invocation outcome does not establish another invocation\'s acceptance, grant permission to resubmit, or authorize changed input or a new restart decision.',
    next: submissionTarget(snapshot),
  });
};

export const projectSubmissionExplanation = (result, outcome, context) => {
  // Called only after admitting the exact Owner response and its binding.
  // Acceptance phase follows its typed branch, never its problem code.
  let explanation;
  if (outcome.kind === 'ready') explanation = {
    observation: 'run_reference_received',
    summary: 'The Host returned a validated Run reference. Check the current Run state for execution progress.',
    next: {operation: 'status', ref: outcome.admission.ref},
  };
  else if (outcome.kind === 'held') explanation = heldRequestExplanation(outcome.held, context);
  else {
    const observation = outcome.kind === 'unresolvable' ? 'history_unresolvable' : outcome.kind;
    const summaries = {
      not_accepted: 'The Host durably rejected this submission before acceptance. Its identity is consumed; no Run reference was returned.',
      preparation_failed: 'The Host accepted this submission, then preparation failed. No Run reference was returned; this is not a rejection before acceptance.',
      preparing: 'The Host accepted this submission and preparation is still pending. No Run reference was returned.',
      history_unresolvable: 'The Host cannot establish the original submission outcome. Work may already have started.',
    };
    explanation = {observation, summary: summaries[observation], hint: submissionObservationHint,
      next: submissionTarget(context),
      ...(['not_accepted', 'preparation_failed'].includes(outcome.kind)
        ? {problem: {code: outcome.problem.code, classification: outcome.problem.classification}} : {})};
  }
  if (explanation.problem?.code === 'ClientProgramAnalysisLimit' &&
      explanation.problem.classification === 'implementation_limit') {
    explanation.preparationIssue = {kind: 'analysis_budget_exhausted',
      summary: 'Preparation reached an analysis budget before all checking obligations were discharged. This does not establish invalid input.',
      hint: 'Inspect a check report for remaining obligations. Keep the original submission reference; any changed input requires a separate submission identity.'};
  }
  if (explanation.problem?.code === 'ClientProgramImplementationLimit' &&
      explanation.problem.classification === 'implementation_limit') {
    explanation.preparationIssue = {kind: 'implementation_limit',
      summary: 'Checking encountered an unresolved implementation path during preparation. This does not establish invalid input.',
      hint: 'Inspect the check report for unresolved support conditions. Keep the original submission reference; any changed input requires a separate submission identity.'};
  }
  return freezeInput(explanation);
};

export const projectRequestLookupExplanation = (answer, context) => {
  const observation = answer.kind === 'found' ? 'run_reference_received' :
    answer.kind === 'not_found' ? 'lookup_unresolved' : 'lookup_unavailable';
  return answer.kind === 'held'
    ? heldRequestExplanation(answer, context) : freezeInput({observation,
      summary: {
        lookup_unresolved: 'This lookup does not establish whether the submission was accepted.',
        lookup_unavailable: 'The Host could not supply a request lookup observation. Acceptance remains unresolved.',
        run_reference_received: 'The Host returned a validated Run reference. Check the current Run state for execution progress.',
      }[observation], hint: requestObservationHint,
      ...(answer.kind === 'found' ? {durability: answer.durability} : {}),
      next: answer.kind === 'found' ? {operation: 'status', ref: {...answer.ref}} :
        {operation: 'lookupRequest', requestId: context.requestId,
          lookupContext: context.lookupContext},
    });
};

export const projectRequestCancellationExplanation = (result, context, observation, problem) => {
  const summaries = {
    accepted: 'The Host recorded cancellation of this request. This response does not establish physical stop or resource release.',
    already_requested: 'The Host reports a previously recorded cancellation of this request. This response does not establish physical stop or resource release.',
    already_terminal: 'The Host reports that this request is already terminal. This response does not establish its execution outcome, physical stop or resource release.',
    outcome_unknown: 'No usable observation of this request cancellation was returned. Durable recording, physical stop and resource release are not established by this observation.',
  };
  return freezeInput({observation,
    requestId: context.requestId, ...(problem === undefined ? {} : {problem}),
    summary: summaries[observation], hint: requestCancellationHint,
    ...(problem === undefined && result.ref !== undefined ? {revision: result.revision} : {}),
    next: problem === undefined && result.ref !== undefined
      ? {operation: 'status', ref: {...result.ref}}
      : {operation: 'lookupRequest', requestId: context.requestId,
        lookupContext: context.lookupContext},
  });
};

export const projectDeliveryLookupFailure = (next, observation) => freezeInput({observation,
    summary: observation === 'lookup_unavailable'
      ? 'The DeliveryAttempt lookup could not be completed. Read opening and delivery remain unresolved.'
      : 'This SDK could not interpret the DeliveryAttempt lookup response. Read opening and delivery remain unresolved.',
    hint: 'Keep this original read reference. This observation does not confirm application receipt or persistence, and grants no permission to reopen or rerun Compute.',
    next,
  });

export const projectSubmissionLookupFailure = (context, observation) => freezeInput({observation,
    summary: observation === 'lookup_unavailable'
      ? 'The submission lookup could not be completed. Acceptance and execution remain unresolved.'
      : 'This SDK could not interpret the submission lookup response. Acceptance and execution remain unresolved.',
    hint: submissionObservationHint, next: submissionTarget(context)});

export const projectRequestLookupFailure = (context, observation) => freezeInput({observation,
    summary: observation === 'lookup_uninterpretable'
      ? 'This SDK could not interpret the request lookup response. Acceptance and execution remain unresolved.'
      : 'The request lookup could not be completed. Acceptance and execution remain unresolved.',
    hint: requestObservationHint,
    next: {operation: 'lookupRequest', requestId: context.requestId,
      lookupContext: context.lookupContext},
  });

export const projectUnavailableRunObservation = (ref, operation) => freezeInput({kind: 'unavailable',
    problem: 'observation_unavailable', operation,
    next: {operation: 'status', ref: {...ref}},
    summary: 'The Run observation could not be completed. Its execution, Effect, publication and release outcomes are not established by this failure.',
    hint: 'Refresh the original Run under current authorization. This observation establishes no execution, Effect, publication or release outcome and grants no write retry.',
  });

export const projectRejectedRunObservation = (ref, operation, problem) => {
  const summaries = {
    unknown_state: 'The Run reply contains a state this SDK cannot interpret.',
    contract_mismatch: 'The Run reply does not match this SDK’s registered state contract.',
    malformed_response: 'The Run reply violates the registered state contract.',
    stale_observation: 'The Run reply has an older control revision or conflicts with previously observed control facts.',
  };
  return freezeInput({
    kind: problem === 'unknown_state' ? 'uninterpretable' : 'protocol_failure',
    problem, operation, summary: summaries[problem],
    hint: 'Refresh the original Run under current authorization. This observation establishes no execution, Effect, publication or release outcome and grants no write retry.',
    next: {operation: 'status', ref: {...ref}},
  });
};

export const projectEffectUncertainty = (state, ref) => {
  if (state.status === 'needs_reconciliation' &&
      state.next_action.kind === 'reconcile') {
    // The observation reader has admitted and detached these exact facts.
    // Presentation must not make another copy that can replace their meaning.
    return freezeInput({
      observation: 'effect_outcome_unknown',
      summary: 'External Effect outcomes are unknown. Computation stop does not establish their outcome or resource release.',
      effects: [...state.next_action.effects],
      physicalStop: state.control?.physical_stop ?? 'unknown',
      ...(state.control === undefined ? {} :
        {controlRevision: state.control.revision}),
      next: {operation: 'reconcile', ref: {...ref}},
    });
  }
};

export const projectSubmissionNotSent = input => freezeInput({observation: 'not_sent',
    summary: 'This SDK did not dispatch this submission attempt. This is not an Owner-issued rejection and does not establish the original identity outcome.',
    hint: submissionObservationHint, next: submissionTarget(input)});
