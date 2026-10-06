// Operation wording is separate from retained observations and wire identity.
import {getCheckPresentationInfo} from './check-presentation.mjs';

const summaries = Object.freeze({
  'observation.unknown_state': 'このSDKではRun応答の状態を解釈できません。',
  'observation.contract_mismatch': 'Run応答がこのSDKの登録済み状態契約と一致しません。',
  'observation.malformed_response': 'Run応答が登録済み状態契約に違反しています。',
  'submission.acceptance_unknown': '送信の受理を確認できません。処理は既に始まっている可能性があります。',
  'submission.request_held': 'Hostは保留中の要求を返しました。元の要求の現在状態を確認してください。',
  'submission.run_reference_received': 'Hostは検証済みのRun参照を返しました。実行の進行はRunの現在状態で確認してください。',
  'cancellation.accepted': 'HostはRunの取消し要求を記録しました。物理停止・Effect・解放はRunの現在状態で確認してください。',
  'cancellation.already_requested': 'Hostは既存のRun取消し要求を報告しました。物理停止・Effect・解放はRunの現在状態で確認してください。',
  'cancellation.already_terminal': 'Hostは取消しについてRunが既に終端状態にあると報告しました。Effect・解放の詳細はRunの現在状態で確認してください。',
  'cancellation.outcome_unknown': 'Run取消しの結果を確認できません。要求は記録されている可能性があります。',
  'effect.effect_outcome_unknown': '外部Effectの結果は未確定です。計算の停止はEffectの結果や資源解放を示しません。',
});
const readHint = 'この読み取り参照を保持してください。先頭から新しく読み取るか判断する前に、元の参照で状態を確認してください。';

export function getOperationPresentationInfo(options) {
  const {locale} = getCheckPresentationInfo(options);
  return Object.freeze({locale, translationRevision: `2026-10-07.operations.${locale}.2`});
}

export function localizeOperation(explanation, domain, options) {
  if (explanation === undefined) return undefined;
  if (getOperationPresentationInfo(options).locale !== 'ja') return explanation;
  const key = domain + '.' + (domain === 'observation' ? explanation.problem : explanation.observation);
  let summary, hint;
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
