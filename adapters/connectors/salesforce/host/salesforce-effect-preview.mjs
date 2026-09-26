import {checked} from '../../../host-common/runtime-result.mjs';
import {inspectSalesforceEffectCapability} from
  '../site/salesforce-effect-capability.mjs';

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

const pendingCid = `sha256:${'0'.repeat(64)}`;

function productPreviewDraft({moon, control, prepared, inputs, context, members,
  requestAuthority, maxWireBytes, maxNodes, maxDepth, planLimits}) {
  if (typeof control?.effectSourceArtifactPreviewBinding !== 'function' ||
      typeof control?.issueSourceFreeLocalEffectIdentity !== 'function' ||
      typeof control?.checkSourceFreeLocalEffectPreviewIdentities !==
        'function' ||
      inputs === undefined ||
      !context?.runDefinition || !context?.runInvocation ||
      !context?.compiledPlan ||
      typeof context.storeAuthorityCid !== 'string' ||
      context.modelDerived !== false ||
      !Array.isArray(members) || members.length === 0) {
    fail('InvalidSalesforceEffectPreviewContext');
  }
  const definitionCid = moon.clientProgramEffectDefinitionCid(prepared);
  const authoring = checked(moon.strategyRunEvidenceSeal(
    'authoring_context', JSON.stringify({
      version: 'actql-authoring-context/0.1',
      program_definition_cid: definitionCid, annotations: [],
    }), maxWireBytes, maxNodes, maxDepth));
  const issuedIdentities = [];
  const draft = {
    version: 'actql-effect-preview/0.1', sensitivity: 'private',
    retention_class: 'authority-evidence', encryption_required: true,
    program_semantics_cid: moon.clientProgramEffectSemanticsCid(prepared),
    program_definition_cid: definitionCid,
    invocation_cid: moon.strategyPublicationContractIdentity(
      context.runInvocation),
    run_identity_cid: moon.strategyPublicationContractIdentity(
      context.runDefinition),
    compiled_plan_cid: moon.strategyPublicationContractIdentity(
      context.compiledPlan),
    check_environment_cid: moon.clientProgramEffectEnvironmentCid(prepared),
    authoring_context: JSON.parse(moon.strategyRunEvidenceJson(authoring)),
    barrier_provenance_cids: [], model_derived: false,
    model_task_contract_cids: [], model_invocation_evidence_cids: [],
    model_response_artifact_cids: [],
    effects: members.map(member => {
      if (!Number.isSafeInteger(member?.stageIndex) ||
          typeof member.effectId !== 'string' ||
          !Array.isArray(member.requests) ||
          !member.localResultArtifact ||
          !member.sourceArtifact ||
          !member.capability ||
          !Array.isArray(member.requiredPermissions) ||
          !Number.isSafeInteger(member.maxItems) ||
          member.maxItems < member.requests.length ||
          typeof member.approval !== 'string' ||
          typeof member.previewStrength !== 'string') {
        fail('InvalidSalesforceEffectPreviewContext');
      }
      if (member.authorityScopeCid !== undefined &&
          member.authorityScopeCid !== requestAuthority) {
        fail('ForeignSalesforceEffectPreviewAuthority');
      }
      const descriptor = checked(moon.clientProgramEffectMemberDescriptor(
        prepared, member.stageIndex, member.effectId, planLimits.maxWork));
      const capability = inspectSalesforceEffectCapability(
        member.capability, member.requests);
      if (descriptor._6 === undefined) {
        fail('MissingSalesforceEffectSourceResult');
      }
      const source = control.effectSourceArtifactPreviewBinding(
        member.sourceArtifact,
        moon.strategyPublicationContractIdentity(context.runInvocation),
        descriptor._6, context.storeAuthorityCid);
      const identity = control.issueSourceFreeLocalEffectIdentity(
        prepared, inputs, descriptor._0, member.localResultArtifact,
        {maxWork: planLimits.maxWork, maxWireBytes, maxNodes, maxDepth});
      issuedIdentities.push(identity);
      return {
        effect_id: descriptor._1, effect_kind: descriptor._2,
        target: descriptor._3, mapping: descriptor._4,
        resolved_mapping_contract_cid: descriptor._5,
        effect_identity_cid: identity.identity,
        ...(descriptor._6 === undefined ? {} :
          {source_result: descriptor._6}),
        result_artifact_cid: source._0,
        preview_strength: member.previewStrength,
        source_binding_cid: source._1,
        capability_evidence_cid: capability.identity,
        authority_scope_cid: requestAuthority,
        write_footprint: {
          kind: 'opaque', provider_boundary_cid: pendingCid,
          provider_namespace: 'pending', resource_kind: 'pending',
          resource_identity_scheme_cid: pendingCid,
          provider_object_identity_cids: [],
        },
        count: member.requests.length, max_items: member.maxItems,
        required_permissions: member.requiredPermissions,
        approval: member.approval,
        on_item_failure: descriptor._7,
        changes: member.requests.map(() => ({
          target_row_identity: 0,
          target_guard: {state: 'not_applicable'},
          intended_changes: {state: 'not_applicable'},
          before: {state: 'not_applicable'},
          after: {state: 'not_applicable'},
          row_preview_cid: pendingCid,
          row_idempotency_key: pendingCid,
        })),
        row_order: [], effect_member_preview_cid: pendingCid,
        executed: false,
      };
    }),
    executed: false, effect_preview_cid: pendingCid,
  };
  return Object.freeze({
    wire: checked(moon.clientProgramCanonicalEffectPreviewDraft(
      JSON.stringify(draft), maxWireBytes, maxNodes, maxDepth)),
    identities: Object.freeze(issuedIdentities),
  });
}

// Only Salesforce's typed request and target observation determine a row's
// target, guard, before, after, and intended changes. This authors no grant or
// apply permit; the checked captured owner must still admit the whole Preview.
export function authorObservedSalesforceEffectPreview({
  moon, salesforceMoon, control, prepared, inputs, templateWire, context,
  requestScope,
  members,
  maxWireBytes, maxNodes, maxDepth, maxRows, maxIdentityBytes,
  maxKeyBytes, maxKeyNodes, maxKeyDepth, planLimits,
}) {
  if (!moon || !salesforceMoon || !prepared || !requestScope ||
      (typeof templateWire !== 'string' && context === undefined) ||
      (typeof templateWire === 'string' && context !== undefined) ||
      !Number.isSafeInteger(maxWireBytes) || maxWireBytes < 1 ||
      maxWireBytes > 1_000_000 ||
      (typeof templateWire === 'string' &&
        Buffer.byteLength(templateWire, 'utf8') > maxWireBytes) ||
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
  const requestAuthority = moon.clientProgramEffectRequestAuthority(
    requestScope);
  let issuedIdentities;
  if (templateWire === undefined) {
    const productDraft = productPreviewDraft({moon, control, prepared, inputs,
      context, members, requestAuthority,
      maxWireBytes, maxNodes, maxDepth, planLimits});
    templateWire = productDraft.wire;
    issuedIdentities = productDraft.identities;
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
    if (proposal?.authority_scope_cid !== requestAuthority) {
      fail('ForeignSalesforceEffectPreviewAuthority');
    }
    if (!Number.isSafeInteger(member?.stageIndex) ||
        member.stageIndex < 0 || typeof member.effectId !== 'string') {
      fail('ForeignSalesforceEffectPreviewMember');
    }
    const descriptor = checked(moon.clientProgramEffectMemberDescriptor(
      prepared, member.stageIndex, member.effectId, planLimits.maxWork));
    if (!proposal || proposal.effect_id !== member.effectId ||
        member.effectId !== descriptor._1) {
      fail('ForeignSalesforceEffectPreviewMember');
    }
    Object.assign(proposal, {
      effect_id: descriptor._1,
      effect_kind: descriptor._2,
      target: descriptor._3,
      mapping: descriptor._4,
      resolved_mapping_contract_cid: descriptor._5,
      on_item_failure: descriptor._7,
    });
    if (descriptor._6 === undefined) {
      delete proposal.source_result;
    } else {
      proposal.source_result = descriptor._6;
    }
    const planCid = checked(moon.clientProgramEffectPlanCid(
      prepared, descriptor._0, planLimits.maxFields, planLimits.maxWork,
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
    const footprint = checked(salesforceMoon.salesforceSingleWriteMemberFootprint(
      member.requests, maxRows - rowCount, maxIdentityBytes));
    proposal.write_footprint = {
      kind: footprint._0,
      provider_boundary_cid: footprint._2,
      provider_namespace: footprint._1,
      provider_object_identity_cids: footprint._5,
      resource_identity_scheme_cid: footprint._3,
      resource_kind: footprint._4,
    };
    proposal.count = member.requests.length;
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
  const draftWire = JSON.stringify(template);
  if (Buffer.byteLength(draftWire, 'utf8') > maxWireBytes) {
    fail('SalesforceEffectPreviewByteLimit');
  }
  const authoredWire = checked(moon.clientProgramCanonicalEffectPreviewDraft(
    draftWire, maxWireBytes, maxNodes, maxDepth));
  const authored = checked(moon.clientProgramAuthorEffectPreview(
    authoredWire, template.run_identity_cid,
    template.authoring_context?.authoring_context_cid,
    requestScope, maxWireBytes, maxNodes, maxDepth, members.length,
    rowCount, maxKeyBytes, maxKeyNodes, maxKeyDepth));
  if (issuedIdentities !== undefined) {
    control.checkSourceFreeLocalEffectPreviewIdentities(
      prepared, inputs, authored._0, template.run_identity_cid,
      template.authoring_context.authoring_context_cid, issuedIdentities,
      {maxWireBytes, maxNodes, maxDepth});
  }
  return Object.freeze({wire: authored._0,
    authoringCid: template.authoring_context.authoring_context_cid,
    keys: authored._1,
    requestOrder: Object.freeze(requestOrder.map(order =>
      Object.freeze(order)))});
}
