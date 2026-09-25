import {checked} from '../host-common/runtime-result.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

const parseExactJson = wire => {
  let value;
  try {
    value = JSON.parse(wire);
  } catch {
    fail('InvalidSalesforceEffectPreviewAuthoring');
  }
  if (JSON.stringify(value) !== wire) {
    fail('LossySalesforceEffectPreviewProjection');
  }
  return value;
};

// Only Salesforce's typed request and target observation determine a row's
// target, guard, before, after, and intended changes. This authors no grant or
// apply permit; the checked captured owner must still admit the whole Preview.
export function authorObservedSalesforceEffectPreview({
  moon, salesforceMoon, prepared, templateWire, requestScope, members,
  maxWireBytes, maxNodes, maxDepth, maxRows, maxIdentityBytes,
  maxKeyBytes, maxKeyNodes, maxKeyDepth, planLimits,
}) {
  if (!moon || !salesforceMoon || !prepared || !requestScope ||
      typeof templateWire !== 'string' ||
      !Number.isSafeInteger(maxWireBytes) || maxWireBytes < 1 ||
      maxWireBytes > 1_000_000 ||
      Buffer.byteLength(templateWire, 'utf8') > maxWireBytes ||
      !Number.isSafeInteger(maxRows) || maxRows < 1 ||
      maxRows > 100_000 ||
      !Array.isArray(members) || members.length === 0 ||
      !Number.isSafeInteger(maxIdentityBytes) || maxIdentityBytes < 1 ||
      maxIdentityBytes > maxWireBytes ||
      !planLimits ||
      !['maxFields', 'maxWork', 'maxBytes', 'maxNodes', 'maxDepth']
        .every(key => Number.isSafeInteger(planLimits[key]) &&
          planLimits[key] > 0)) {
    fail('InvalidSalesforceEffectPreviewAuthoring');
  }
  let template;
  try {
    template = JSON.parse(templateWire);
  } catch {
    fail('InvalidSalesforceEffectPreviewAuthoring');
  }
  if (!Array.isArray(template.effects) ||
      template.effects.length !== members.length ||
      template.program_definition_cid !==
        moon.clientProgramEffectDefinitionCid(prepared) ||
      template.program_semantics_cid !==
        moon.clientProgramEffectSemanticsCid(prepared) ||
      template.check_environment_cid !==
        moon.clientProgramEffectEnvironmentCid(prepared)) {
    fail('InvalidSalesforceEffectPreviewAuthoring');
  }
  let rowCount = 0;
  let projectedBytes = Buffer.byteLength(templateWire, 'utf8');
  const requestOrder = [];
  for (const [memberIndex, member] of members.entries()) {
    const proposal = template.effects[memberIndex];
    const descriptor = checked(moon.clientProgramEffectMemberDescriptor(
      prepared, memberIndex));
    if (!proposal || member?.effectId !== descriptor._0) {
      fail('ForeignSalesforceEffectPreviewMember');
    }
    Object.assign(proposal, {
      effect_id: descriptor._0,
      effect_kind: descriptor._1,
      target: descriptor._2,
      mapping: descriptor._3,
      resolved_mapping_contract_cid: descriptor._4,
      on_item_failure: descriptor._6,
    });
    if (descriptor._5 === undefined) {
      delete proposal.source_result;
    } else {
      proposal.source_result = descriptor._5;
    }
    const planCid = checked(moon.clientProgramEffectPlanCid(
      prepared, memberIndex, planLimits.maxFields, planLimits.maxWork,
      planLimits.maxBytes, planLimits.maxNodes, planLimits.maxDepth));
    if (planCid === undefined) {
      delete proposal.effect_plan_logical_cid;
    } else {
      proposal.effect_plan_logical_cid = planCid;
    }
    if (!Array.isArray(member?.requests) ||
        (proposal?.effect_kind !== 'create' &&
          (!Array.isArray(member?.observations) ||
            member.requests.length !== member.observations.length)) ||
        !Array.isArray(proposal?.changes) ||
        proposal.changes.length !== member.requests.length ||
        !['create', 'update', 'upsert'].includes(proposal.effect_kind) ||
        member.requests.length > proposal.max_items ||
        rowCount + member.requests.length > maxRows) {
      fail('InvalidSalesforceEffectPreviewAuthoring');
    }
    rowCount += member.requests.length;
    if (proposal.effect_kind === 'create') {
      const afterWires = [];
      for (const [rowIndex, request] of member.requests.entries()) {
        if (salesforceMoon.salesforceSingleWriteRequestEffectKind(request) !==
            'create') {
          fail('ForeignSalesforceEffectPreviewObservation');
        }
        const bodyWire = salesforceMoon.salesforceSingleWriteRequestBody(request);
        const bodyBytes = typeof bodyWire === 'string' ?
          Buffer.byteLength(bodyWire, 'utf8') : maxWireBytes;
        if (typeof bodyWire !== 'string' ||
            bodyBytes > (maxWireBytes - projectedBytes) / 2) {
          fail('SalesforceEffectPreviewByteLimit');
        }
        const body = parseExactJson(bodyWire);
        if (body === null || Array.isArray(body) || typeof body !== 'object') {
          fail('InvalidSalesforceEffectPreviewAuthoring');
        }
        projectedBytes += bodyBytes * 2;
        const after = {state: 'present', value: body};
        afterWires.push(JSON.stringify(after));
        proposal.changes[rowIndex] = {
          ...proposal.changes[rowIndex],
          target_guard: {state: 'not_applicable'},
          before: {state: 'absent'},
          after,
          intended_changes: {state: 'present', value: body},
        };
      }
      const inventory = checked(moon.clientProgramEffectCreateRowInventory(
        afterWires, member.requests.length, maxWireBytes,
        maxNodes, maxDepth));
      const original = proposal.changes;
      proposal.changes = inventory.map(entry => ({
        ...original[entry._0],
        target_row_identity: parseExactJson(entry._1),
      }));
      requestOrder.push(inventory.map(entry => entry._0));
      continue;
    }
    requestOrder.push(member.requests.map((_, index) => index));
    for (const [rowIndex, request] of member.requests.entries()) {
      const observation = member.observations[rowIndex];
      if (!observation?.record || observation.request !== request) {
        fail('ForeignSalesforceEffectPreviewObservation');
      }
      const row = checked(salesforceMoon.salesforcePrepareObservedPreviewRow(
        request, observation.record, maxIdentityBytes));
      const fields = salesforceMoon.salesforceObservedPreviewRowFields(row);
      if (!Array.isArray(fields) || fields.length !== 5 ||
          salesforceMoon.salesforceSingleWriteRequestEffectKind(request) !==
            proposal.effect_kind) {
        fail('ForeignSalesforceEffectPreviewObservation');
      }
      for (const field of fields) {
        if (typeof field !== 'string' ||
            Buffer.byteLength(field, 'utf8') > maxWireBytes - projectedBytes) {
          fail('SalesforceEffectPreviewByteLimit');
        }
        projectedBytes += Buffer.byteLength(field, 'utf8');
      }
      proposal.changes[rowIndex] = {
        ...proposal.changes[rowIndex],
        target_row_identity: parseExactJson(fields[0]),
        target_guard: {state: 'version', version_cid: fields[1]},
        before: {state: 'present', value: parseExactJson(fields[2])},
        after: {state: 'present', value: parseExactJson(fields[3])},
        intended_changes: {state: 'present', value: parseExactJson(fields[4])},
      };
    }
  }
  const authoredWire = JSON.stringify(template);
  if (Buffer.byteLength(authoredWire, 'utf8') > maxWireBytes) {
    fail('SalesforceEffectPreviewByteLimit');
  }
  const authored = checked(moon.clientProgramAuthorEffectPreview(
    authoredWire, template.run_identity_cid,
    template.authoring_context?.authoring_context_cid,
    requestScope, maxWireBytes, maxNodes, maxDepth, members.length,
    rowCount, maxKeyBytes, maxKeyNodes, maxKeyDepth));
  return Object.freeze({wire: authored._0,
    authoringCid: template.authoring_context.authoring_context_cid,
    keys: authored._1,
    requestOrder: Object.freeze(requestOrder.map(order =>
      Object.freeze(order)))});
}
