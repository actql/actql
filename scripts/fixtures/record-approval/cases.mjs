// Independent authored inputs/oracles. These do not supply a Catalog, Mapping,
// grant or execution support. Ordinary factories must provide those separately.
const select = value => {
  for (const key of ['recordId', 'previousName', 'nextName']) {
    if (typeof value?.[key] !== 'string' || !value[key]) throw new TypeError('InvalidRecordApprovalSelection');
  }
  if (value.previousName === value.nextName) throw new TypeError('UnchangedRecordApprovalSelection');
  return value;
};

// Authored normal-fixture DATA shared by the logical Mock and the provider's
// HTTP fixture. This does not select a runtime, Account, revision or grant.
export const sharedRecordUpdateSelections = Object.freeze({
  hubspot: Object.freeze({recordId: '9007199254740993', controlId: '9007199254740994',
    previousName: 'Before HubSpot approval', nextName: 'After HubSpot approval'}),
  kintone: Object.freeze({recordId: '9007199254740993', controlId: '9007199254740994',
    previousName: 'Before kintone approval', nextName: 'After kintone approval'}),
});

export const maxRecordUpdateFixtureTextUnits = 16_384;

export function recordUpdateFixtureSeed({recordId, previousName, controlId, controlName = 'Untouched control'},
  {allowAbsent = false} = {}) {
  const absent = allowAbsent && previousName === null;
  if (typeof recordId !== 'string' || !recordId || !absent && (typeof previousName !== 'string' || !previousName)) {
    throw new TypeError('InvalidRecordApprovalSelection');
  }
  if (typeof controlId !== 'string' || !controlId || controlId === recordId || typeof controlName !== 'string') {
    throw new TypeError('InvalidRecordApprovalControl');
  }
  if ([recordId, previousName, controlId, controlName].some(text =>
    text !== null && text.length > maxRecordUpdateFixtureTextUnits)) {
    throw new RangeError('RecordApprovalFixtureSeedLimit');
  }
  return Object.freeze({target: absent ? null : Object.freeze({id: recordId, name: previousName}),
    control: Object.freeze({id: controlId, name: controlName})});
}

export function recordUpdateFixtureState(selected) {
  const {recordId, nextName} = select(selected);
  const before = recordUpdateFixtureSeed(selected);
  return Object.freeze({
    before,
    after: Object.freeze({target: Object.freeze({id: recordId, name: nextName}), control: before.control}),
  });
}

export function salesforceUpdateCase(programs, selected) {
  const {recordId, previousName, nextName} = select(selected);
  return {name: 'salesforce-account-update',
    effect: {document: programs.update, format: 'aql', resultName: 'updates',
      parameterDeclarations: {record_id: {type: 'string'}, next_name: {type: 'string'}},
      parameters: {record_id: recordId, next_name: nextName},
      expectedRows: [{Id: recordId, previous_name: previousName, next_name: nextName}]},
    read: {document: programs.read, format: 'aql', resultName: 'main',
      parameterDeclarations: {record_id: {type: 'string'}}, parameters: {record_id: recordId},
      beforeRows: [{Id: recordId, Name: previousName}], afterRows: [{Id: recordId, Name: nextName}]},
    review: {target: 'connector://salesforce/Account', identity: recordId,
      before: {Name: previousName}, changes: {Name: nextName}}};
}

// A separate Program for HubSpot's own original field names. The exact same
// bytes are used for its mock and installed route; no string rewriting occurs.
// A fixture result alone does not qualify the ordinary installed Effect route.
export function hubspotUpdateCase(programs, selected) {
  const {recordId, previousName, nextName} = select(selected);
  return {name: 'hubspot-company-update',
    effect: {document: programs.update, format: 'aql', resultName: 'updates',
      parameterDeclarations: {record_id: {type: 'string'}, next_name: {type: 'string'}},
      parameters: {record_id: recordId, next_name: nextName},
      expectedRows: [{id: recordId, previous_name: previousName, next_name: nextName}],
      ...(selected.variant === 'binary-source' ? {additionalResults: {
        answer: [{id: recordId, left_name: previousName, right_id: recordId,
          right_name: previousName, next_name: nextName}],
      }} : {})},
    read: {document: programs.read, format: 'aql', resultName: 'main',
      parameterDeclarations: {record_id: {type: 'string'}}, parameters: {record_id: recordId},
      beforeRows: [{id: recordId, name: previousName}], afterRows: [{id: recordId, name: nextName}]},
    review: {target: 'connector://hubspot/companies', identity: recordId,
      before: {name: previousName}, changes: {name: nextName}}};
}

// Kintone system record ids remain exact strings, including values above 2^53.
export function kintoneUpdateCase(programs, selected) {
  const {recordId, previousName, nextName} = select(selected);
  return {name: 'kintone-record-update',
    effect: {document: programs.update, format: 'aql', resultName: 'updates',
      parameterDeclarations: {record_id: {type: 'string'}, next_name: {type: 'string'}},
      parameters: {record_id: recordId, next_name: nextName},
      expectedRows: [{id: recordId, previous_name: previousName, next_name: nextName}]},
    read: {document: programs.read, format: 'aql', resultName: 'main',
      parameterDeclarations: {record_id: {type: 'string'}}, parameters: {record_id: recordId},
      beforeRows: [{id: recordId, Subject: previousName}], afterRows: [{id: recordId, Subject: nextName}]},
    review: {target: 'connector://kintone/inquiries', identity: recordId,
      before: {Subject: previousName}, changes: {Subject: nextName}}};
}


// Existing shared HTTPS fixture fault DATA only. A provider owns the exact
// write route; this does not issue a request, classify Run state or grant send.
export function recordUpdateReplyLossFaults(provider) {
  const {method, pathname, bodyIncludes} = provider?.writeRequest ?? {};
  if (typeof method !== 'string' || !/^[A-Z]{3,16}$/u.test(method) ||
      typeof pathname !== 'string' || !pathname.startsWith('/') ||
      pathname.startsWith('//') || pathname.length > 4096 || !pathname.isWellFormed() ||
      pathname.includes('?') || pathname.includes('#') ||
      pathname.includes(String.fromCharCode(0)) || pathname.includes(String.fromCharCode(92)) ||
      (bodyIncludes !== undefined && (typeof bodyIncludes !== 'string' ||
        bodyIncludes.length < 1 || bodyIncludes.length > 128 || !bodyIncludes.isWellFormed()))) {
    throw new TypeError('InvalidRecordApprovalWriteRoute');
  }
  return Object.freeze([Object.freeze({kind: 'apply-then-lose-reply', method, pathname, times: 1,
    ...(bodyIncludes === undefined ? {} : {bodyIncludes})})]);
}
