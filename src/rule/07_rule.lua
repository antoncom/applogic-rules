local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Мигание светодиода LED2 - режим связи (2G, 3G или 4G)",
	},
	sim_id = {
		note = [[ Идентификатор активной Сим-карты: 0/1. ]],
        source = {
			type = "ubus",
            object = "tsmodem.driver",
            method = "sim",
            params = {},
        },
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]]
		}
    },

    network_registration = {
		note = [[ Статус регистрации Сим-карты в сети 0..7. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "reg",
			params = {},
			--filter = "value"
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},

	switching = {
		note = [[ Статус переключения Sim: true / false. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "switching",
			params = {},
			cached = "no" -- Turn OFF caching of the var, as next rule may use non-actual value
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_frozen"] = [[ if ($switching == "true") then return 10 else return 0 end ]],
		}
	},

    netmode = {
		note = [[ Режим сети 2G/3G/4G ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "netmode",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_ui-update"] = {
				param_list = { "sim_id", "netmode" }
			}
		}
	},

    -- LED2_mode = {
    --     note = [[ Режим мигания светодиода LED2. ]],
    --     modifier = {
    --         ["1_func"] = [[
    --                         local no_blinking = "v0"
    --                         local mode_1 = { name = "2G", blinking = "f200,200,200,800" }
    --                         local mode_2 = { name = "3G", blinking = "f200,200,200,200,200,800" }
    --                         local mode_3 = { scale = "4G", blinking = "f200,200,200,200,200,200,200,800" }
    --                         if $network_registration ~= "1" then return no_blinking
	-- 							elseif $switching == "true" then return no_blinking
	-- 							elseif $netmode == "2G" then return mode_1.blinking
    --                             elseif  $netmode == "3G" then return mode_2.blinking
    --                             elseif  $netmode == "4G" then return mode_3.blinking
    --                             else return no_blinking
    --                         end
    --                      ]],
    --     },
    -- },

	-- send_stm_at = {
	-- 	note = [[ Отправка настроек светодиода LED2 ]],
	-- 	source = {
	-- 		type = "ubus",
	-- 		object = "tsmodem.stm",
	-- 		method = "send",
	-- 		params = {
    --             command = "~0:LED.2=$LED2_mode",
    --         },
	-- 	},
	-- 	modifier = {
    --         ["1_skip"] = [[
    --             return ($LED2_mode == $previous)
    --         ]]
    --     }
    -- },

    -- previous = {
    --     note = [[ Режим мигания светодиода LED2 (на предыдущей итерации). ]],
    --     modifier = {
    --         ["1_func"] = [[
    --                         return $LED2_mode
    --                      ]],
    --     },
    -- },
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
-- Alternatively, you may run debug via shell like this "applogic 06_rule title sim_id" (use 5 variable names maximum)
function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	self:load("title"):modify():debug()
	self:load("sim_id"):modify():debug()
    self:load("network_registration"):modify():debug()
	self:load("switching"):modify():debug()
    self:load("netmode"):modify():debug()
	-- self:load("LED2_mode"):modify():debug()
	-- self:load("send_stm_at"):modify():debug()
    -- self:load("previous"):modify():debug()
end


---[[ Initializing. Don't edit the code below ]]---
local metatable = {
	__call = function(table, parent)
		local t = rule_init(table, rule_setting, parent)
		if not t.is_busy then
			t.is_busy = true
			t:make()
			t.is_busy = false
		end
		return t
	end
}
setmetatable(rule, metatable)
return rule
