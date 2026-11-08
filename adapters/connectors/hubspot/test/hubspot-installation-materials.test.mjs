import * as moon from '../../../../_build/js/release/build/connectors/hubspot/host_node/host_node.js';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {registerHubSpotInstallationMaterialTests} from './hubspot-installation-materials.fixture.mjs';
registerHubSpotInstallationMaterialTests(moon, common);
