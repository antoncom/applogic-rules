local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Мигание светодиода LED3 - какая сим активна",
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

	switching = {
		note = [[ Статус переключения Sim: true / false. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "switching",
			params = {},
			--cached = "no" -- Turn OFF caching of the var, as next rule may use non-actual value
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_frozen"] = [[ if ($switching == "true") then return 10 else return 0 end ]],
		}
	},

	r01_sim_ready = {
		note = [[ Значение sim_ready из правила 01_rule ]],
		source = {
			type = "rule",
			rulename = "01_rule",
			varname = "sim_ready"
		},
	},

    LED3_mode = {
        note = [[ Режим мигания светодиода LED3. ]],
        modifier = {
            ["1_func"] = [[
                            local no_blinking = "v0"
                            local mode_1 = { sim_id = "0", blinking = "f200,800" }
                            local mode_2 = { sim_id = "1", blinking = "f200,200,200,800" }
                            if $switching == "true" then return no_blinking
							elseif  ($sim_id == "0" and $r01_sim_ready == "true") then return mode_1.blinking
							elseif  ($sim_id == "1" and $r01_sim_ready == "true") then return mode_2.blinking
                            else return no_blinking end
                         ]],
        },
    },

	send_stm_at = {
		note = [[ Отправка настроек светодиода LED3 ]],
		source = {
			type = "ubus",
			object = "tsmodem.stm",
			method = "send",
			params = {
				command = "~0:LED.3=$LED3_mode",
			},
		},
		modifier = {
			["1_skip"] = [[
				return ($LED3_mode == $previous)
			]]
		}
	},

    previous = {
        note = [[ Режим мигания светодиода LED3 (на предыдущей итерации). ]],
        modifier = {
            ["1_func"] = [[
                            return $LED3_mode
                         ]],
        },
    },
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
-- Alternatively, you may run debug via shell like this "applogic 07_rule title sim_id" (use 5 variable names maximum)
function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	self:load("title"):modify():debug()
	self:load("sim_id"):modify():debug()
	self:load("switching"):modify():debug()
	self:load("r01_sim_ready"):modify():debug()
	self:load("LED3_mode"):modify():debug()
	self:load("send_stm_at"):modify():debug()
    self:load("previous"):modify():debug()
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
