// Independent authored inputs/oracles. These do not supply a Catalog, Mapping,
// grant or execution support. Ordinary factories must provide those separately.
const select = value => {
  for (const key of ['recordId', 'previousName', 'nextName']) {
    if (typeof value?.[key] !== 'string' || !value[key]) throw new TypeError('InvalidRecordApprovalSelection');
  }
  if (value.previousName === value.nextName) throw new TypeError('UnchangedRecordApprovalSelection');
  return value;
};

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
// The descriptor is not a claim that an ordinary HubSpot Effect is connected.
export function hubspotUpdateCase(programs, selected) {
  const {recordId, previousName, nextName} = select(selected);
  return {name: 'hubspot-company-update',
    effect: {document: programs.update, format: 'aql', resultName: 'updates',
      parameterDeclarations: {record_id: {type: 'string'}, next_name: {type: 'string'}},
      parameters: {record_id: recordId, next_name: nextName},
      expectedRows: [{id: recordId, previous_name: previousName, next_name: nextName}]},
    read: {document: programs.read, format: 'aql', resultName: 'main',
      parameterDeclarations: {record_id: {type: 'string'}}, parameters: {record_id: recordId},
      beforeRows: [{id: recordId, name: previousName}], afterRows: [{id: recordId, name: nextName}]},
    review: {target: 'connector://hubspot/companies', identity: recordId,
      before: {name: previousName}, changes: {name: nextName}}};
}
