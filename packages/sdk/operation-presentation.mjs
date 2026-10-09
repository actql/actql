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
  return Object.freeze({locale, translationRevision: `2026-10-09.operations.${locale}.12`});
}

export function localizeOperation(explanation, domain, options) {
  if (explanation === undefined) return undefined;
  if (getOperationPresentationInfo(options).locale !== 'ja') return explanation;
  let key = domain + '.' + (domain === 'observation' ? explanation.problem : explanation.observation);
  if ((domain === 'request' || domain === 'submission') && explanation.observation === 'request_held') {
    key = 'request.request_held.' + explanation.preparationState;
  }
  if (domain === 'cancellation' && ['refused', 'conflict'].includes(explanation.observation)) {
    key += '.' + explanation.reason;
  }
  let summary, hint;
  if (domain === 'request' || domain === 'submission' && explanation.observation === 'request_held') {
    hint = '元の要求参照を保持し、認可された照会を使ってください。この観測は再送信・実行・Checkpointへの回答・資源解放を許可しません。';
  }
  if (domain === 'submission' && explanation.hint !== undefined && explanation.observation !== 'request_held') {
    hint = '元の提出参照を保持し、認可された照会を使ってください。この観測は再送信・実行・資源解放を許可しません。';
  }
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
