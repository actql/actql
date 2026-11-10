import {readFile} from 'node:fs/promises';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as native from '../../../../_build/js/release/build/connectors/hubspot/host_node/host_node.js';
import {registerHubSpotMappingParentTests} from './hubspot-mapping-parent.fixture.mjs';
registerHubSpotMappingParentTests(common, native,
  await readFile(new URL('../../../../spec/local-check-environment.json', import.meta.url), 'utf8'));
