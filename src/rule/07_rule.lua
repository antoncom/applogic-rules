local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Мигание светодиода LD4 - какая сим активна",
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


    LED4_mode = {
        note = [[ Режим мигания светодиода LED4. ]],
        modifier = {
            ["1_func"] = [[
                            local no_blinking = "v0"
                            local mode_1 = { sim_id = "0", blinking = "f200,800" }
                            local mode_2 = { sim_id = "1", blinking = "f200,200,200,800" }
                            if $sim_id == 0 then return mode_1.blinking
                                elseif $sim_id == 1 then return mode_2.blinking
                                else return no_blinking
                            end
                         ]],
        },
    },

	send_stm_at = {
		note = [[ Отправка настроек светодиода LD4 ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "send_stm_at",
			params = {
                sub_sys = "LED",
                param = "4",
                arg = "$LED4_mode"
            },
		},
        modifier = {
            ["1_skip"] = [[
                return ($LED4_mode == $previous)
            ]]
        }
    },

    previous = {
        note = [[ Режим мигания светодиода LED4 (на предыдущей итерации). ]],
        modifier = {
            ["1_func"] = [[
                            return $LED4_mode
                         ]],
        },
    },
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug mode: RULE or VAR
-- Use :debug("INFO") - to debug single variable in the rule (ERROR also is possible)

function rule:make()
	rule.debug_mode = debug_mode
	debug_mode.type = "RULE"
	debug_mode.level = "ERROR"
	local ONLY = rule.debug_mode.level

	self:load("title"):modify():debug()
	self:load("sim_id"):modify():debug()
	self:load("LED4_mode"):modify():debug()
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
