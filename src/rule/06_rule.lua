local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Мигание светодиода LED1 - уровень сигнала",
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

	signal = {
		note = [[ Уровень сигнала сотового оператора, %. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "signal",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
			["2_func"] = [[ if (tonumber($signal)) then return $signal else return "-" end ]],
		},
	},

    LED1_mode = {
        note = [[ Режим мигания светодиода LED1 ]],
        modifier = {
            ["1_func"] = [[
                local no_blinking = "v0"
                local mode_1 = { scale = 25, blinking = "f200,800" }
                local mode_2 = { scale = 50, blinking = "f200,200,200,800" }
                local mode_3 = { scale = 75, blinking = "f200,200,200,200,200,800" }
                local mode_4 = { scale = 100, blinking = "f200,200,200,200,200,200,200,800" }
				local signal = tonumber($signal) or 0
                if $network_registration ~= "1" then return no_blinking
					elseif (signal == 0) then return no_blinking
					elseif ($switching == "true") then return no_blinking
					elseif (signal <= mode_1.scale) then return mode_1.blinking
	                elseif (signal > mode_1.scale and signal <= mode_2.scale) then return mode_2.blinking
	                elseif (signal > mode_2.scale and signal <= mode_3.scale) then return mode_3.blinking
	                elseif (signal > mode_3.scale and signal <= mode_4.scale) then return mode_4.blinking
					else return no_blinking
                end
             ]],
        },
    },


	send_stm_at = {
		note = [[ Отправка настроек светодиода LED1 ]],
		source = {
			type = "ubus",
			object = "tsmodem.stm",
			method = "send",
			params = {
                command = "~0:LED.1=$LED1_mode",
            },
		},
		modifier = {
            ["1_skip"] = [[
                return ($LED1_mode == $previous)
            ]]
        }
    },

	previous = {
		note = [[ Режим мигания светодиода LED1 (на предыдущей итерации). ]],
		modifier = {
			["1_func"] = [[
							return $LED1_mode
						 ]],
		},
	},
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
-- Alternatively, you may run debug via shell like this "applogic 05_rule title sim_id" (use 5 variable names maximum)
function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	self:load("title"):modify():debug()
	self:load("sim_id"):modify():debug()
    self:load("network_registration"):modify():debug()
	self:load("switching"):modify():debug()
    self:load("signal"):modify():debug()
	self:load("LED1_mode"):modify():debug()
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
