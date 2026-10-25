import {validCheckOutcome} from '@actql/client-wire';
import {selectCheckReasonPresentation} from './check-reason-catalog.generated.js';
import {freezeInput, utf8} from './internal/data.mjs';
// Translation data is separate from wire semantics and checking authority.
// English Reason defaults come from the generated public catalog; a missing or malformed
// translation uses that same safe default without changing the observation.
const japanese = Object.freeze(Object.fromEntries(Object.entries({
  'reason.numeric_reduction_profile_required': ['この集計に必要な数値還元profileが検査文脈で受理されていません。',
    '検査文脈の管理者に、参照CIDの固定profileの設定を依頼し、束縛された入力全体を再検査してください。profileへの所属だけでは還元方式の選択や実行は認可されません。'],
  'reason.host_capacity_policy_required': ['検査文脈でHost容量policyが選択されていません。',
    '検査文脈の管理者に、参照schemaで受理されるpolicyの設定を依頼し、束縛された入力全体を再検査してください。'],
  'reason.checking_context_missing': ['必要な検査文脈の入力が不足しています。',
    '公開されたRequirementを検査文脈の管理者と確認してください。無関係なパラメータ値を補っても充足しません。'],
  'protocol.unknown_outcome': ['このSDKでは検査応答のoutcomeを解釈できません。',
    'HostとSDKの契約対応を確認してください。この観測は検査判定や再試行許可を示しません。'],
  'protocol.contract_mismatch': ['検査応答がこのSDKの登録済みprotocol identityと一致しません。',
    'HostとSDKの契約を揃えてください。拒否された応答は検査判定を示しません。'],
  'protocol.malformed_response': ['検査応答が登録済み応答契約または元入力のbindingに違反しています。',
    'Hostの管理者にprotocol失敗の調査を依頼してください。入力誤りの診断ではありません。'],
  'limit.function_lowering_unresolved': ['式lowererがこの関数形式を判定・対応できません。',
    '元の式での関数対応を検査文脈の管理者に確認してください。関数名の誤りが確定した診断ではありません。'],
  'omissions.requirements': ['Hostは既知の不足入力の一部を省略しました。省略件数は公開しません。',
    '判定は元の検査範囲を保持します。この一覧は補足入力の完全なfrontierではありません。'],
  'completed.invalid': ['検査範囲内の入力違反が確認されました。',
    '開示された理由を確認し、示された提出時のrevisionを修正してください。'],
  'completed.verified': ['この報告が検証するのは、束縛された検査範囲と文脈だけです。',
    '実行・取消し・解放の結果は、それぞれのOwnerで確認してください。'],
  'completed.undetermined': ['検査範囲内では、検証成功も確定した入力違反も判断できません。',
    '不足する入力と開示された検査限界を確認してください。未充足条件は入力誤りではありません。'],
  'failed.check_report_unbounded': ['報告用の予算内では、束縛された検査報告全体を作成できませんでした。',
    '元の検査範囲について、検査文脈の管理者に報告容量の確認を依頼してください。'],
  'failed.check_internal': ['検査内部の失敗により、束縛された検査報告全体を作成できませんでした。',
    '検査文脈の管理者に報告失敗の調査を依頼してください。'],
  'failed.unknown': ['束縛された検査報告全体を作成できませんでした。この問題コードに対応する説明はありません。',
    '検査文脈の管理者に調査を依頼してください。部分報告は入力の検証成功を示しません。'],
  unavailable: ['安全な公開報告に必要な検査範囲と文脈を利用できません。',
    '検査文脈の管理者に公開文脈の確認を依頼してください。この応答は入力誤りを示しません。'],
  'reason.query_syntax_invalid': ['クエリの構文が不正です。',
    '位置が示されている場合は、その位置のクエリ構文を修正してください。'],
  'reason.query_expression_invalid': ['式が参照・引数・数値の契約に違反しています。',
    '選択されたクエリ契約に従って式を修正してください。'],
  'reason.query_frame_invalid': ['analytic ROWS frameの境界が有効な区間になっていません。',
    '両境界がPRECEDINGなら開始距離を終了距離以上に、両境界がFOLLOWINGなら開始距離を終了距離以下にしてください。'],
  'reason.query_lexical_invalid': ['クエリのトークンが字句構文に違反しています。',
    '位置が示されている場合は、その位置のトークンを修正してください。'],
  'reason.parameter_undeclared': ['クエリが未宣言のパラメータを参照しています。',
    'パラメータを宣言するか参照を修正してください。値を渡すだけでは宣言になりません。'],
  'reason.parameter_unused': ['宣言されたパラメータがProgram全体で使用されていません。',
    '未使用の宣言を削除するかProgramで参照し、再検査してください。'],
  'reason.query_invalid': ['クエリが言語または名前解決の契約に違反しています。',
    '宣言された名前と公開文脈に従ってクエリを修正してください。'],
  'reason.parameter_declarations_invalid': ['パラメータ宣言が不正です。', '提出した宣言を修正してください。'],
  'reason.supplied_parameters_invalid': ['提出したパラメータ入力が不正です。', '提出したパラメータmapを修正してください。'],
  'reason.supplied_value_invalid': ['渡された値が宣言に違反しています。', '宣言された契約を満たすように値を修正してください。'],
  'reason.supplied_value_constraint_violation': ['渡された値が宣言された制約を満たしていません。',
    '宣言された制約の種類に従って値を修正してください。'],
  'reason.supplied_value_type_mismatch': ['渡された値の型が宣言と一致しません。', '宣言された型の値を渡してください。'],
  'reason.parameter_value_required': ['宣言されたパラメータの値が不足しています。',
    '宣言された値を補い、束縛された入力全体を再検査してください。'],
  'reason.parameter_default_type_mismatch': ['パラメータの既定値が宣言された型と一致しません。',
    '宣言された型に合わせて既定値を修正し、再検査してください。'],
  'expression_domain.key_comparable_operands': ['式のオペランドの型に互換性がありません。',
    'この演算では、相互に互換性のある型のオペランドを使用してください。'],
  'expression_domain.matching_numeric_domains': ['算術演算のオペランドが同じ対応数値領域に属していません。',
    '対応する同じ数値領域のオペランドを使用してください。'],
  'carrier.expected_relation': ['この演算にはRelation入力が必要です。',
    'この演算の前にRelationを用意してください。現在のcarrierはRelationではありません。'],
  'carrier.expected_vectors': ['この演算にはVectors入力が必要です。',
    'この演算の前にVectorsを用意してください。例えば、互換性のあるRelationをto_vectorsで変換できます。'],
  'reason.expression_type_mismatch': ['式が必要な引数型に違反しています。', '必要な型を持つ引数を使用してください。'],
  'expression_type.number': ['式の引数にはnumber型が必要です。', '拒否された引数にはnumber型の式を使用してください。'],
  'expression_type.boolean': ['式の引数にはboolean型が必要です。', '拒否された引数にはboolean型の式を使用してください。'],
  'expression_type.string': ['式の引数にはstring型が必要です。', '拒否された引数にはstring型の式を使用してください。'],
  'reason.operation_parameter_invalid': ['パラメータが演算のscalar領域に違反しています。',
    '示された演算領域に従って、渡した値または使用された既定値を修正してください。'],
  'scalar.positive_safe_integer': ['演算パラメータには正のsafe integerが必要です。',
    '1以上9007199254740991以下の整数を渡してください。'],
  'scalar.nonnegative_safe_integer': ['演算パラメータには非負のsafe integerが必要です。',
    '0以上9007199254740991以下の整数を渡してください。負のゼロは受理されません。'],
  'scalar.unit_fraction': ['演算パラメータには0以上1以下の有限な割合が必要です。',
    '両端を含む0以上1以下の数値を渡してください。負のゼロは受理されません。'],
  'scalar.finite_number': ['演算パラメータには有限な数値が必要です。',
    '有限な数値を渡してください。負のゼロは受理されません。'],
  'scalar.duration': ['演算パラメータには受理可能なdurationが必要です。',
    '正のASCII数字にms・s・m・h・dを続けた、空白のない文字列を渡してください。ミリ秒値はsafe integerの範囲内である必要があります。'],
  'scalar.positive_milliseconds': ['演算パラメータには正のsafe integerミリ秒または受理可能なdurationが必要です。',
    '正のsafe integerミリ秒値、またはms・s・m・h・dを使った正のduration文字列を渡してください。'],
  'scalar.signed_milliseconds': ['演算パラメータには符号付きsafe integerミリ秒または受理可能なdurationが必要です。',
    '-9007199254740991以上9007199254740991以下で負のゼロを除く整数ミリ秒値、または正のduration文字列を渡してください。'],
  'scalar.timestamp': ['演算パラメータには受理可能なtimestamp値が必要です。',
    'timestamp宣言の契約で受理される、nullでないtimestamp値を渡してください。'],
  'reason.program_invalid': ['入力が検査対象のProgram契約に違反しています。', '選択された契約に従って入力を修正してください。'],
  'reason.bound_values_missing': ['必要な束縛入力が不足しています。', '宣言された入力を補い、再検査してください。'],
  'reason.implementation_limit': ['この検査実装では未充足条件を解消できません。',
    '検査文脈の管理者に、提出した構文の対応状況を確認してください。'],
  'reason.analysis_budget_exhausted': ['解析用の予算を使い切りました。', '検査文脈の管理者に解析予算の確認を依頼してください。'],
  'reason.check_unclassified': ['checkerが分類された結論を確定できませんでした。', '検査文脈の管理者に調査を依頼してください。'],
  'reason.unresolved_protected': ['開示された文脈ではSource解決を確定できません。',
    'Sourceまたは検査文脈の管理者に公開文脈の確認を依頼してください。'],
  'reason.unknown': ['この理由に対応する説明はありません。'],
  'lexical.unexpected_end': ['トークンが完成する前に入力が終わっています。',
    '示された位置の引用トークンまたはescape sequenceを完成させてください。'],
  'lexical.unexpected_token': ['この字句文脈ではトークンが不正です。', '示された位置のトークン表記または区切りを修正してください。'],
  'lexical.invalid_escape': ['escape sequenceが不正です。', '選択された文字列または識別子構文で許可されるescapeを使用してください。'],
  'lexical.invalid_scalar': ['トークンに字句文脈で許可されないscalarが含まれています。',
    '選択された字句構文に従ってscalar escapeまたは引用識別子を修正してください。'],
  'lexical.empty_identifier': ['引用された識別子が空です。', '引用区切りの中に空でない識別子を指定してください。'],
  'lexical.unterminated_comment': ['block commentが閉じられていません。', 'block commentの終了区切りを追加してください。'],
  'lexical.invalid_number': ['数値トークンの表記が不正です。', '指数表記を含め、数値トークンを修正してください。'],
  'lexical.invalid_parameter': ['パラメータ参照に有効な名前がありません。', '@の後に有効なパラメータ名を指定してください。'],
  'expression.expected_boolean': ['predicateの型はBooleanである必要があります。', 'predicateには比較式などのBoolean条件を使用してください。'],
  'expression.unknown_reference': ['検査範囲内で式の参照を解決できません。', '開示されたクエリ文脈で宣言された参照を使用してください。'],
  'expression.invalid_arguments': ['式の引数が選択された演算契約に違反しています。',
    '選択された演算が必要とする引数の数または形式に修正してください。'],
  'expression.invalid_number': ['数値式が受理可能な数値領域の外にあります。',
    '受理可能な精度とsigned-zeroの領域内で有限の数値を使用してください。'],
  'components.invalid_kind': ['componentsのkindが不正です。', 'componentsのkindにはweakまたはstrongを指定してください。'],
  'components.invalid_output_rows': ['componentsの出力行数上限が不正です。', 'componentsのmax_output_rowsには正のsafe integerを指定してください。'],
  'subgraph.invalid_node_selector': ['Subgraphのnode selectorが不正です。',
    '空でないids、id fieldを持つ名前付きRelation、またはnode where predicateのいずれか一つを指定してください。'],
  'constraint.numeric': ['渡された値が宣言された制約を満たしていません。',
    '宣言された整数・最小値・最大値の制約を満たす数値を渡してください。'],
  'constraint.duration': ['渡された値が宣言された制約を満たしていません。', '受理可能なduration形式の文字列を渡してください。'],
  'constraint.array_length': ['渡された値が宣言された制約を満たしていません。', '宣言された正確な長さの配列を渡してください。'],
  'constraint.array_size': ['渡された値が宣言された制約を満たしていません。', '宣言された最大要素数以内の配列を渡してください。'],
}).map(([key, value]) => [key, Object.freeze(value)])));

export function getCheckPresentationInfo(options) {
  let locale = 'en';
  try {
    const requested = options?.locale;
    if (requested === 'ja' || requested === 'ja-JP') locale = 'ja';
  } catch { /* Locale lookup cannot hide a validated observation. */ }
  return Object.freeze({locale, translationRevision: `2026-10-25.${locale}.11`});
}

export function localizeCheck(key, english, options) {
  const locale = getCheckPresentationInfo(options).locale;
  const translated = locale === 'ja' && Object.hasOwn(japanese, key) ? japanese[key] : undefined;
  return Array.isArray(translated) && translated.length === english.length &&
    translated.every(value => typeof value === 'string' && value.length > 0 && value.length <= 2048)
    ? translated : english;
}

export function explainCheckOutcome(outcome, options) {
  if (!validCheckOutcome(outcome)) return undefined;
  const reportExplanation = (report, completeness) => ({completeness,
    verdict: report.verdict, scope: {...report.scope}, contextRef: report.context_ref,
    ...(report.omissions === undefined ? {} : {omissions: {...report.omissions}})});
  if (outcome.outcome === 'completed') {
    const explanations = {
      invalid: ['The report establishes an input violation in its checking scope.',
        'Review the disclosed reasons and correct the submitted revision where indicated.'],
      verified: ['The report verifies only its selected checking scope and context.',
        'Use the execution, cancellation and release owners for their respective results.'],
      undetermined: ['The report cannot establish verification or a proven input violation in its checking scope.',
        'Review missing inputs and disclosed checking limits; an outstanding obligation is not an input error.'],
    };
    // Capture observation fields before reading application-owned locale options.
    const report = reportExplanation(outcome.report, 'complete');
    const [summary, hint] = localizeCheck(`completed.${report.verdict}`,
      explanations[report.verdict], options);
    return freezeInput({outcome: 'completed', summary, hint, report});
  }
  if (outcome.outcome === 'failed') {
    const explanations = {
      check_report_unbounded: ['The reporting budget could not produce a complete bound check report.',
        'Ask the checking-context owner to review reporting capacity for the original checking scope.'],
      check_internal: ['An internal checking failure prevented a complete bound check report.',
        'Ask the checking-context owner to investigate the reporting failure.'],
    };
    const known = Object.hasOwn(explanations, outcome.problem.code);
    const problem = {kind: known ? 'known' : 'unknown', code: outcome.problem.code};
    const correlationRef = outcome.correlation_ref;
    const report = outcome.partial_report === undefined ? undefined
      : reportExplanation(outcome.partial_report, 'partial');
    const [summary, hint] = localizeCheck(`failed.${known ? problem.code : 'unknown'}`,
      known ? explanations[problem.code]
      : ['A complete bound check report could not be issued; this problem code has no supported explanation.',
        'Ask the checking-context owner to investigate; a partial report does not verify the input.'], options);
    return freezeInput({outcome: 'failed', summary, hint, correlationRef, problem,
      ...(report === undefined ? {} : {report})});
  }
  const problem = {kind: outcome.problem.code === 'check_unavailable' ? 'known' : 'unknown',
    code: outcome.problem.code};
  const correlationRef = outcome.correlation_ref;
  const [summary, hint] = localizeCheck('unavailable',
    ['The scope and checking context needed for a safe public report are unavailable.',
      'Ask the checking-context owner to review the published context; this response does not establish an input error.'], options);
  return freezeInput({outcome: 'unavailable', summary, hint, problem, correlationRef});
}


// Presentation formats consume the disclosed report, never internal causes.
// Escape untrusted controls and bidi marks without changing source identity.

const checkDisplayString = value => JSON.stringify(value).replace(
  /[\u007f-\u009f\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]/gu,
  character => '\\u' + character.charCodeAt(0).toString(16).padStart(4, '0'));

const checkHtml = value => value.replace(/[&<>"']/gu, character =>
  ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'})[character]);

const checkAgentJson = value => JSON.stringify(value).replace(
  /[<>&\u007f-\u009f\u061c\u200e\u200f\u2028-\u202e\u2066-\u2069]/gu,
  character => '\\u' + character.charCodeAt(0).toString(16).padStart(4, '0'));

/** Format a validated public observation without granting actions or input access. */

export function renderCheckOutcome(outcome, options, resolveCheckLocation, resolveCheckTextRangeEncoding) {
  let snapshot;
  try {
    if (!validCheckOutcome(outcome)) return undefined;
    snapshot = JSON.parse(JSON.stringify(outcome));
    if (!validCheckOutcome(snapshot)) return undefined;
  } catch { return undefined; }
  let format, maxBytes, currentInputs, locale, positionEncoding;
  try {
    format = options?.format ?? 'text';
    maxBytes = options?.maxBytes ?? 65536;
    currentInputs = options?.currentInputs;
    positionEncoding = options?.positionEncoding ?? 'utf-16';
  } catch { return undefined; }
  try { locale = options?.locale; } catch { locale = 'en'; }
  if (!['text', 'html', 'json'].includes(format) || !['utf-8', 'utf-16', 'utf-32'].includes(positionEncoding) || !Number.isSafeInteger(maxBytes) ||
      maxBytes < 1024 || maxBytes > 1048576) return undefined;
  const presentation = getCheckPresentationInfo({locale});
  const observation = explainCheckOutcome(snapshot, {locale: presentation.locale});
  const report = snapshot.outcome === 'completed' ? snapshot.report : snapshot.partial_report;
  const rows = report === undefined ? [] : [
    ...report.reasons.map(reason => ({kind: 'violation', reason})),
    ...report.requirements.map(reason => ({kind: 'requirement', reason})),
    ...report.coverage.limits.map(reason => ({kind: 'limit', reason})),
    ...report.coverage.unresolved.map(({reason, boundary}) =>
      ({kind: 'unresolved', reason: {code: reason}, boundary})),
  ];
  const entries = [];
  const model = () => ({observation, presentation, entries, omittedEntries: rows.length - entries.length,
    reasonSchemaCid: snapshot.reason_schema_cid, outcomeSchemaCid: snapshot.outcome_schema_cid});
  const line = entry => entry.kind + ': ' + checkDisplayString(entry.code) + ' ' + entry.summary +
    (entry.hint === undefined ? '' : ' ' + entry.hint) +
    (entry.facts === undefined ? '' : ' facts=' + checkDisplayString(entry.facts)) +
    (entry.boundary === undefined ? '' : ' boundary=' + checkDisplayString(entry.boundary)) +
    (entry.location === undefined ? '' : ' location=' + checkDisplayString(entry.location));
  const render = () => {
    if (format === 'json') return checkAgentJson(model());
    const heading = observation.outcome +
      (observation.report === undefined ? '' : '/' + observation.report.verdict +
        ' (' + observation.report.completeness + ')') + ': ' + observation.summary;
    const binding = observation.report === undefined ?
      'Correlation: ' + checkDisplayString(observation.correlationRef) :
      'Scope: ' + observation.report.scope.kind + '; context_ref: ' + checkDisplayString(observation.report.contextRef);
    const omitted = rows.length - entries.length;
    const suffix = [omitted ? `Omitted entries: ${omitted}. The observation above is unchanged.` : '',
      report?.omissions?.requirements ? localizeCheck('omissions.requirements',
        ['The Host omitted some known input requirements; no omitted count is exposed.',
          'The verdict still covers the original scope; this requirement list is not a complete supplementation frontier.'],
        {locale: presentation.locale}).join(' ') : ''].filter(Boolean).join(' ');
    if (format === 'html') return '<section><h2>' + checkHtml(heading) + '</h2><p>' +
      checkHtml(observation.hint) + '</p><p>' + checkHtml(binding) + '</p><ol>' + entries.map(entry => '<li>' +
        checkHtml(line(entry)) + '</li>').join('') + '</ol><p>' + checkHtml(suffix) + '</p></section>';
    return [heading, observation.hint, binding, ...entries.map(line), suffix].filter(Boolean).join('\n');
  };
  let output = render();
  if (utf8.encode(output).length > maxBytes) return undefined;
  for (const row of rows) {
    const explanation = explainCheckReason(row.reason, {locale: presentation.locale});
    const {kind: explanationKind, ...display} = explanation;
    const entry = {kind: row.kind, code: row.reason.code, ...display, explanationKind};
    if (explanation.kind === 'known' && row.reason.facts !== undefined) entry.facts = row.reason.facts;
    if (row.boundary !== undefined) entry.boundary = row.boundary;
    try {
      const location = row.reason.location;
      const current = currentInputs === undefined ? undefined :
        Array.isArray(currentInputs) ? currentInputs.find(input => input?.documentId === location?.document_id) : undefined;
      // An explicitly supplied current-input set never silently uses older input.
      const resolved = currentInputs !== undefined && current === undefined ? undefined :
        resolveCheckLocation(outcome, location, current);
      if (resolved) {
        entry.location = {kind: resolved.kind, documentId: resolved.document_id, revision: resolved.revision,
          ...(resolved.kind === 'structured' ? {pointer: resolved.pointer} :
            {startByte: resolved.start_byte, endByte: resolved.end_byte, precision: resolved.precision})};
        const range = resolved.kind === 'text' && resolveCheckTextRangeEncoding(outcome, location, positionEncoding, current);
        if (range) Object.assign(entry.location, {positionEncoding: range.positionEncoding, range: range.range});
      }
    } catch { /* Missing or malformed editor input cannot hide safe explanations. */ }
    entries.push(entry);
    const candidate = render();
    if (utf8.encode(candidate).length > maxBytes) { entries.pop(); break; }
    output = candidate;
  }
  return output;
}

// Reason presentation does not decide the report's verdict or outcome branch.

export function explainCheckReason(reason, options) {
  const display = selectCheckReasonPresentation(reason);
  if (display) {
    const [summary, hint] = localizeCheck(display.key, display.english, options);
    return Object.freeze({kind: 'known', summary, hint});
  }
  const [summary] = localizeCheck('reason.unknown', ['No supported explanation is available for this reason.'], options);
  return Object.freeze({kind: 'unknown', summary});
}

export function presentCheckFailure(failure, options) {
  const messages = {
    unknown_outcome: ['The check reply contains an outcome this SDK cannot interpret.',
      'Review Host and SDK contract support; this observation establishes no check verdict or retry permission.'],
    contract_mismatch: ['The check reply does not match this SDK’s registered protocol identities.',
      'Use matching Host and SDK contracts; the rejected reply establishes no check verdict.'],
    malformed_response: ['The check reply violates the registered response contract or original input binding.',
      'Ask the Host owner to investigate the protocol failure; it is not a diagnosed source error.'],
  };
  const [summary, hint] = localizeCheck(`protocol.${failure.problem}`, messages[failure.problem], options);
  return freezeInput({kind: failure.kind, problem: failure.problem, summary, hint});
}
