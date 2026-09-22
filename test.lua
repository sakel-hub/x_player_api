-- Unified BDD Test Runner for x_player_api
-- Executes modular test suites under tests/specs/

package.path = "./?.lua;./?/init.lua;" .. package.path

local framework = require("tests.framework")
local mock_env = require("tests.mock_env")

-- Initialize mock environment and mod files
mock_env.init()

-- Expose describe/it/assert globals to specs
framework.expose_globals()

require("tests.specs.environment_spec")
require("tests.specs.wield_offsets_spec")
require("tests.specs.wield_entity_spec")
require("tests.specs.wield_settings_spec")
require("tests.specs.eating_spec")
require("tests.specs.controls_spec")
require("tests.specs.model_spec")
require("tests.specs.equip_sound_spec")
require("tests.specs.proxies_spec")
require("tests.specs.legacy_b3d_spec")
require("tests.specs.pure_native_b3d_spec")
require("tests.specs.b3d_wiggler_spec")

-- Run the test suite
local ok = framework.run()
if not ok then
	os.exit(1)
end
