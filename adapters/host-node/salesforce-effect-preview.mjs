import {checked} from '../host-common/runtime-result.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

// Only Salesforce's typed request and target observation determine a row's
// target, guard, before, after, and intended changes. This authors no grant or
// apply permit; the checked captured owner must still admit the whole Preview.
export function authorObservedSalesforceEffectPreview({
  moon, salesforceMoon, templateWire, requestScope, members,
  maxWireBytes, maxNodes, maxDepth, maxRows, maxIdentityBytes,
  maxKeyBytes, maxKeyNodes, maxKeyDepth,
}) {
  if (!moon || !salesforceMoon || !requestScope ||
      typeof templateWire !== 'string' ||
      !Number.isSafeInteger(maxWireBytes) || maxWireBytes < 1 ||
      maxWireBytes > 1_000_000 ||
      Buffer.byteLength(templateWire, 'utf8') > maxWireBytes ||
      !Number.isSafeInteger(maxRows) || maxRows < 1 ||
      maxRows > 100_000 ||
      !Array.isArray(members) || members.length === 0 ||
      !Number.isSafeInteger(maxIdentityBytes) || maxIdentityBytes < 1 ||
      maxIdentityBytes > maxWireBytes) {
    fail('InvalidSalesforceEffectPreviewAuthoring');
  }
  let template;
  try {
    template = JSON.parse(templateWire);
  } catch {
    fail('InvalidSalesforceEffectPreviewAuthoring');
  }
  if (!Array.isArray(template.effects) ||
      template.effects.length !== members.length) {
    fail('InvalidSalesforceEffectPreviewAuthoring');
  }
  let rowCount = 0;
  let projectedBytes = Buffer.byteLength(templateWire, 'utf8');
  for (const [memberIndex, member] of members.entries()) {
    const proposal = template.effects[memberIndex];
    if (!Array.isArray(member?.requests) ||
        !Array.isArray(member?.observations) ||
        member.requests.length !== member.observations.length ||
        !Array.isArray(proposal?.changes) ||
        proposal.changes.length !== member.requests.length ||
        !['update', 'upsert'].includes(proposal.effect_kind) ||
        member.requests.length > proposal.max_items ||
        rowCount + member.requests.length > maxRows) {
      fail('InvalidSalesforceEffectPreviewAuthoring');
    }
    rowCount += member.requests.length;
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
        target_row_identity: JSON.parse(fields[0]),
        target_guard: {state: 'version', version_cid: fields[1]},
        before: {state: 'present', value: JSON.parse(fields[2])},
        after: {state: 'present', value: JSON.parse(fields[3])},
        intended_changes: {state: 'present', value: JSON.parse(fields[4])},
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
    keys: authored._1});
}
