import {refusedEffectPreparation} from '../host-common/effect-preparation-result.mjs';
import {issueUpdateTargetInstallation, issueUpdateTargetInstallationData, assertUpdateTargetSelectionCurrent,
  assertUpdateTargetSelectionCurrentData} from './update-target-original-shape.mjs';
import type {retainUpdateTargetSelection, UpdateTargetRuntime} from './update-target-original-shape.mjs';
import type {InstalledConnectorEntry} from '../../packages/local-node/index.d.ts';

type Installation = ReturnType<typeof issueUpdateTargetInstallation>;
type InstallationRuntime = Pick<UpdateTargetRuntime, 'clientProgramIssueEffectTargetInstallation'> &
  Partial<Pick<UpdateTargetRuntime, 'clientProgramIssueEffectTargetInstallationData'>>;
type IdentityProfile = NonNullable<NonNullable<InstalledConnectorEntry['effect']>['identityProfile']>;
type InstalledMapping = Readonly<{
  target: string; resource: string; mappingRef: string; mappingCid: string;
  rules: readonly Readonly<{effect_kind: string}>[];
}>;
type InstallationOwner = Readonly<{
  moon: InstallationRuntime;
  connectorRegistration: string; connectorRevision: string;
  runtimeBundleCid: string; bindingCid: string; continuationBinding: string;
  connection: string; profile: IdentityProfile; authorization: object;
  installed: readonly InstalledMapping[]; storeMappings: readonly InstalledMapping[];
}>;
type TargetReadBinding = Readonly<{installationOwnerCid: string; installationBindingCid: string; targetRef: string}>;
type SelectionOwner = Pick<NonNullable<ReturnType<typeof retainUpdateTargetSelection>>[number], 'installation_owner_cid'>;
type OwnerControls = Readonly<{
  rowInstallations: Pick<WeakMap<object, InstallationOwner | readonly InstallationOwner[]>, 'get'>;
  installedEffectKinds(owner: InstallationOwner): readonly string[];
}>;

export function createInstalledRowEffectOwnerProjection({rowInstallations, installedEffectKinds}: OwnerControls) {
  // This is the existing installation projection used by composed recovery.
  // Its canonical bytes identify an owner without admitting structural copies
  // of an adapter or introducing another installation registry.
  const installationFacts = (owner: InstallationOwner) => ({
    connector_registration: owner.connectorRegistration,
    connector_revision: owner.connectorRevision,
    runtime_bundle_cid: owner.runtimeBundleCid, binding_cid: owner.bindingCid,
    connection: owner.connection, profile: owner.profile,
    continuation_binding: owner.continuationBinding,
  });
  const ownerBinding = (owner: InstallationOwner) => issueUpdateTargetInstallation(owner.moon, installationFacts(owner));
  function installedRowEffectOwnerBinding(adapter: unknown) {
    const owner = rowInstallations.get(adapter as object);
    return owner === undefined || Array.isArray(owner) ? undefined : ownerBinding(owner as InstallationOwner);
  }

  // Borrow only the actual installed owner's metadata-read scopes. Target names
  // and equal CIDs cannot manufacture an adapter, Account or execution grant.
  function installedRowEffectUpdateTargetReadAccess(adapter: unknown, target: TargetReadBinding) {
    const retained = rowInstallations.get(adapter as object);
    const owners = retained === undefined ? [] : Array.isArray(retained) ? retained as readonly InstallationOwner[] : [retained as InstallationOwner];
    let selected: InstallationOwner | undefined;
    for (const owner of owners) {
      if (ownerBinding(owner).cid !== target.installationOwnerCid ||
          owner.bindingCid !== target.installationBindingCid) continue;
      if (selected !== undefined) return undefined;
      selected = owner;
    }
    if (selected === undefined) return undefined;
    const resources: string[] = [];
    for (const mapping of selected.installed) {
      if (mapping.target === target.targetRef && !resources.includes(mapping.resource)) {
        resources.push(mapping.resource);
      }
    }
    if (resources.length === 0) return undefined;
    return {authorization: selected.authorization, connection: selected.connection, resources};
  }

  const selectionChanged = (cause?: unknown): never => {
    throw refusedEffectPreparation(Object.assign(
      new Error('InstalledRowEffectInstallationChanged', {cause}),
      {code: 'InstalledRowEffectInstallationChanged'}));
  };
  const updateObservation = (owner: InstallationOwner, installation = ownerBinding(owner)) => ({installation,
    update: installedEffectKinds(owner).includes('update'),
    ...(installedEffectKinds(owner).includes('delete') ? {delete: true} : {}),
    ...(owner.storeMappings.length === 0 ? {} : {store: true}),
    mappings: owner.installed.map(mapping => ({
      target: mapping.target, mappingRef: mapping.mappingRef, mappingCid: mapping.mappingCid,
      update: mapping.rules.some(rule => rule.effect_kind === 'update'),
      ...(mapping.rules.some(rule => rule.effect_kind === 'delete') ? {delete: true} : {}),
      ...(owner.storeMappings.includes(mapping) ? {store: true} : {})}))});
  const updateObservations = (owners: readonly InstallationOwner[]) => owners.map(owner => updateObservation(owner));

  const updateInstallationProjection = (owner: InstallationOwner) =>
    typeof owner.moon.clientProgramIssueEffectTargetInstallationData !== 'function'
      ? undefined : issueUpdateTargetInstallationData(owner.moon as Required<Pick<UpdateTargetRuntime, 'clientProgramIssueEffectTargetInstallationData'>>, [
        owner.bindingCid, owner.connection, owner.connectorRegistration,
        owner.connectorRevision, owner.continuationBinding, owner.profile.continuation,
        owner.profile.continuationBinding, owner.profile.dispatch, owner.profile.recovery,
        owner.profile.source, owner.profile.targetCheck, owner.profile.unit, owner.runtimeBundleCid,
      ]);

  // One synchronous physical projection. Issue each genuine singular owner's
  // DATA once, preserve ambiguity refusal before Mapping reads, then borrow the
  // selected issuance for its current purpose/Mapping observation. Nothing is
  // retained between calls and Common still validates the complete observation.
  function installedRowEffectUpdateObservation(adapters: unknown, ownerCid: string) {
    if (!Array.isArray(adapters)) return undefined;
    const matches: {owner: InstallationOwner; installation: Installation; data: unknown}[] = [];
    for (const adapter of adapters) {
      const owner = rowInstallations.get(adapter as object);
      if (owner === undefined || Array.isArray(owner)) continue;
      // The private physical Owner supplies scalar slots, never untrusted DATA.
      // Its profile is the closed frozen installation-table snapshot. Missing
      // typed ports keep the existing complete raw path for older components.
      const projection = updateInstallationProjection(owner as InstallationOwner);
      const installation = projection?.installation ?? ownerBinding(owner as InstallationOwner);
      if (installation.cid === ownerCid) matches.push({owner, installation, data: projection?.data} as (typeof matches)[number]);
    }
    if (matches.length !== 1) return undefined;
    const {owner, installation, data} = matches[0];
    const observation = updateObservation(owner, installation);
    return data === undefined ? observation : {...observation, installationData: data};
  }

  // These are the caller's three fresh, synchronous current-observation Maps.
  // Borrow their observation slots for private owner references until every
  // physical CID is resolved. No Mapping is read before ambiguity refusal, and
  // neither typed DATA nor an owner index survives this one current call.
  function collectInstalledRowEffectUpdateObservations(adapters: unknown, selections: readonly SelectionOwner[],
    originals: Map<string, Installation>, observations: Map<string, unknown>, installationData: Map<string, unknown>) {
    if (!Array.isArray(adapters)) return false;
    if (selections.length === 0) return true;
    for (const adapter of adapters) {
      const owner = rowInstallations.get(adapter as object);
      if (owner === undefined || Array.isArray(owner)) continue;
      const projection = updateInstallationProjection(owner as InstallationOwner);
      const installation = projection?.installation ?? ownerBinding(owner as InstallationOwner);
      let selected = false;
      for (const selection of selections) {
        if (selection.installation_owner_cid === installation.cid) selected = true;
      }
      if (!selected) continue;
      if (originals.has(installation.cid)) return false;
      originals.set(installation.cid, installation);
      observations.set(installation.cid, owner);
      if (projection?.data !== undefined) installationData.set(installation.cid, projection.data);
    }
    for (const selection of selections) {
      if (!originals.has(selection.installation_owner_cid)) return false;
    }
    // Actual installations are frozen, but a legacy caller can supply a mutable
    // adapter vector. Refuse replacement/duplication during a physical bridge
    // before turning its earlier owner observation into current Mapping facts.
    for (const owner of observations.values()) {
      let occurrences = 0;
      for (const adapter of adapters) {
        if (rowInstallations.get(adapter as object) === owner) occurrences++;
      }
      if (occurrences !== 1) return false;
    }
    for (const [ownerCid, owner] of observations) {
      const observation = updateObservation(owner as InstallationOwner, originals.get(ownerCid));
      if (installationData.has(ownerCid)) {
        const {installation, ...currentFacts} = observation;
        observations.set(ownerCid, currentFacts);
      } else observations.set(ownerCid, observation);
    }
    return true;
  }
  const validateOwnerSelections = <Selections,>(owners: readonly InstallationOwner[], selections: Selections, prepared: unknown) => {
    if (selections === undefined) return undefined;
    try {
      // These call-local DATA slots replace the full embedded installation
      // strings and their decoder/cursor scratch in the same current phase.
      // Their coexisting representation fits that removed work; no retained
      // cache, larger limit or new resource grant is introduced here.
      const observations: ReturnType<typeof updateObservation>[] = [], installations: unknown[] = [];
      for (const owner of owners) {
        // Fresh physical DATA, not a retained validation or authorization grant.
        // Common still checks the same preparation, purpose and Mapping at each
        // use, including the virtual bounds of the complete installation wire.
        const projection = updateInstallationProjection(owner);
        observations.push(updateObservation(owner, projection?.installation));
        if (projection !== undefined) installations.push(projection.data);
      }
      if (installations.length === 0) {
        assertUpdateTargetSelectionCurrent(selections, observations, prepared);
      } else {
        if (installations.length !== observations.length) selectionChanged();
        // These are new private observation records. Reuse them without another
        // wrapper while removing the wire that the same opaque DATA represents.
        for (const observation of observations) delete (observation as Partial<typeof observation>).installation;
        assertUpdateTargetSelectionCurrentData(selections, observations, installations, prepared);
      }
    }
    catch (cause) { selectionChanged(cause); }
    return selections;
  };

  // Current physical installation facts; semantic matching stays in Common.
  function installedRowEffectUpdateObservations(adapter: unknown) {
    const owner = rowInstallations.get(adapter as object);
    return updateObservations(owner === undefined ? [] : Array.isArray(owner) ? owner as readonly InstallationOwner[] : [owner as InstallationOwner]);
  }

  // The Host has already checked the original Core selection owners. This
  // boundary additionally binds those tuples to the actual installed driver.
  function validateInstalledUpdateOwnerSelections<Selections>(adapter: unknown, selections: Selections, prepared: unknown) {
    const owner = rowInstallations.get(adapter as object);
    return validateOwnerSelections(owner === undefined ? [] :
      Array.isArray(owner) ? owner as readonly InstallationOwner[] : [owner as InstallationOwner], selections, prepared);
  }

  return {installationFacts, selectionChanged, validateOwnerSelections, installedRowEffectOwnerBinding,
    installedRowEffectUpdateTargetReadAccess, installedRowEffectUpdateObservation,
    collectInstalledRowEffectUpdateObservations, installedRowEffectUpdateObservations, validateInstalledUpdateOwnerSelections};
}
