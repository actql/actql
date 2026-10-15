// Connector-owned Command data and request hooks. Catalog admission, Ref
// admission, approval, claims, response capture and recovery stay common.
import {canonicalJson as valueJson} from '../../../../packages/sdk/host-port.mjs';
import {contentCid} from '../../../host-node/local-account-config.mjs';
import {prepareSheetsUpdate, projectSheetsUpdate, sendSheetsUpdate,
  sheetsUpdateRequestCid, SHEETS_UPDATE_OPERATION} from '../site/sheets-exchange.mjs';

const canonical = value => valueJson(value, {dataKeys: true});
const same = (a, b) => canonical(a) === canonical(b);
const fail = code => { throw Object.assign(new Error(code), {code}); };
const recoveryKind = 'sheets-range-request';

export function sheetsRangeCommand(connectorId, site) {
  const fields = Object.fromEntries(site.columns.map(column => [column.name,
    {type: column.type, nullable: false}]));
  const row = {type: 'object', nullable: false, additional_properties: false, fields};
  const inputFields = {rows: {type: 'array', nullable: false,
    max_items: site.gridRange.endRow - site.gridRange.startRow, items: row}};
  const contract = (kind, fields) => {
    const body = {schema: 'actql.contract/0.1', id: `${connectorId}.sheets.${kind}`,
      version: 'sheets/0.1', kind,
      body: {type: 'object', nullable: false, additional_properties: false, fields}};
    return {...body, cid: contentCid(body)};
  };
  const input = contract('command_input', inputFields);
  const output = contract('command_output', {
    spreadsheet_id: {type: 'string', nullable: false},
    sheet_id: {type: 'number', nullable: false},
    acknowledged_rows: {type: 'number', nullable: false}});
  const ref = value => ({id: value.id, version: value.version, cid: value.cid});
  const body = {schema: 'actql.command_contract/0.1',
    command_id: `command:${connectorId}.sheets.update_range.v0.1`,
    connector_id: connectorId, version: 'sheets/0.1',
    target: {resource_kind: 'sheet_range', cardinality: 'single'},
    input_schema: ref(input), output_schema: ref(output),
    input_contract: {additional_properties: false, fields: inputFields},
    permissions: [SHEETS_UPDATE_OPERATION], minimum_approval: 'required',
    preview: {strength: 'exact'}, outcome: 'synchronous',
    idempotency: {support: 'unsupported'}, reversibility: 'unknown', atomicity: 'single_target'};
  const command = {...body, contract_cid: contentCid(body)};
  return Object.freeze({command, contracts: [input, output],
    installed: {resource: 'range_target', commandRef: command.command_id,
      commandCid: command.contract_cid, body: canonical(command)}});
}

// SourceView/schema generation is still the opaque row declaration Owner's.
// These provider-owned Command contracts are added as ordinary Catalog data;
// the existing CheckEnvironment validates their complete identities/dependencies.
export function withSheetsRangeCommand(declared, rangeCommand) {
  const {catalog_cid: _, ...catalog} = JSON.parse(declared.catalog);
  const contracts = [...declared.contracts.map(JSON.parse), ...rangeCommand.contracts]
    .sort((a, b) => a.cid < b.cid ? -1 : a.cid > b.cid ? 1 : 0);
  const body = {...catalog, commands: [rangeCommand.command], contracts};
  const catalogCid = contentCid(body);
  return Object.freeze({...declared, catalog_cid: catalogCid,
    catalog: canonical({...body, catalog_cid: catalogCid}), contracts: contracts.map(canonical)});
}

export function sheetsRangeReference({site, catalogCid, bindingCid}) {
  return Object.freeze({$actql_ref: 'resource', version: 'actql-resource-ref/0.1',
    provider_namespace: 'sheets', resource_kind: 'sheet_range',
    provider_identity_cid: contentCid({version: 'actql-sheets-provider/0.1',
      api_origin: site.apiOrigin, spreadsheet_id: site.spreadsheetId}),
    identity_cid: contentCid({version: 'actql-sheets-range/0.1', range: site.gridRange}),
    authority_scope_cid: bindingCid, boundary_cid: catalogCid});
}

export function createSheetsRangeDriver({moon, site, command, bindingCid,
  target, isCurrent}) {
  const requests = new WeakSet();
  // Retain original installation material once. Recovery never derives the
  // historical range/schema from a replacement current configuration.
  const original = JSON.parse(canonical({version: 'actql-sheets-range-recovery/0.1',
    bindingCid, commandCid: command.commandCid, origin: site.apiOrigin,
    spreadsheetId: site.spreadsheetId, range: site.gridRange, columns: site.columns, target}));
  const admitTarget = value => {
    if (!isCurrent() || !same(value, original.target)) fail('SheetsRangeReferenceUnavailable');
  };
  const prepare = (value, target, saved = original) => {
    admitTarget(target);
    const request = prepareSheetsUpdate({moon, ...saved, value, target});
    requests.add(request);
    return request;
  };
  const admitRequest = request => {
    admitTarget(request.target);
    if (!requests.has(request) || request.requestCid !== sheetsUpdateRequestCid(request)) {
      fail('ForeignSheetsRangeRequest');
    }
  };
  return Object.freeze({kinds: ['command'], writeOperation: () => SHEETS_UPDATE_OPERATION,
    prepareRequest({member, value, selector}) {
      if (member.resource !== 'range_target') fail('UndeclaredSheetsResource');
      const request = prepare(value, selector);
      return {request, requestCid: request.requestCid};
    },
    requestFacts: request => ({value: request.value, target: request.target}),
    requestCid: request => { admitRequest(request); return request.requestCid; },
    recheckRequests({entries}) { for (const entry of entries) admitRequest(entry.request); },
    recoveryEntry({member}) {
      const body = {...original, effectId: member.effectId};
      return {kind: recoveryKind, wire: canonical(body), observationCid: contentCid(body)};
    },
    recoverRequests({body, durable}) {
      const saved = durable.connectorRecovery;
      if (!Array.isArray(saved) || saved.length !== body.effects.length) fail('SheetsRangeRecoveryMismatch');
      const recovered = body.effects.map((member, index) => {
        const entries = saved.filter(entry => entry.memberIndex === index && entry.kind === recoveryKind);
        if (entries.length !== 1 || member.effect_kind !== 'command' ||
            member.resolved_command_contract_cid !== command.commandCid) fail('SheetsRangeRecoveryMismatch');
        const entry = entries[0];
        if (typeof entry.wire !== 'string' || Buffer.byteLength(entry.wire) > 100_000) fail('SheetsRangeRecoveryMismatch');
        let value;
        try { value = JSON.parse(entry.wire); } catch { fail('SheetsRangeRecoveryMismatch'); }
        if (entry.wire !== canonical(value) || entry.observationCid !== contentCid(value) ||
            !same(value, {...original, effectId: member.effect_id})) fail('SheetsRangeRecoveryMismatch');
        return member.changes.map(change => prepare(change.intended_changes.value,
          change.target_row_identity, value));
      });
      return {currents: body.effects.map(() => undefined), requests: recovered};
    },
    async send(options) { admitRequest(options.request); return sendSheetsUpdate(options); },
    project: options => projectSheetsUpdate({...options, moon}),
    footprint: () => ({providerNamespace: 'sheets', resourceKind: 'sheet_range',
      boundaryCid: original.target.boundary_cid})});
}
