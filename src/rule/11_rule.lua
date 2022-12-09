local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило журналирования событий Микроконтроллера",
	},

	event_datetime = {
		note = [[ Дата события. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "stm32",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.time ]],
			["2_func"] = [[ if tonumber($event_datetime) then return(os.date("%Y-%m-%d %H:%M:%S", $event_datetime)) else return "" end ]]
		}
	},

	event_stm_is_new = {
		note = [[ Признак новых данных от STM32. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "stm32",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.unread ]],
		}
	},

	event_stm_command = {
		note = [[ Последняя команда, отправленная на STM32. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "stm32",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.command ]],
		}
	},


	event_stm_value = {
		note = [[ Ответ на последнюю команду от STM32. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "stm32",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},


	journal = {
		note = [[ Отправка данных в Журнал событий в Web-интерфейсе. ]],
		modifier = {
			["1_skip"] = [[ return not ($event_stm_is_new == "true") ]],
			["2_func"] = [[return({
					datetime = $event_datetime,
					name = "]] .. I18N.translate("Executing the command") .. [[",
					source = "]] .. I18N.translate("Microcontroller") .. [[",
					command = $event_stm_command,
					response = $event_stm_value
				})]],
			["3_ui-update"] = {
				param_list = { "journal" }
			}
		}
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
	self:load("event_datetime"):modify():debug()
	self:load("event_stm_is_new"):modify():debug()
	self:load("event_stm_command"):modify():debug()
	self:load("event_stm_value"):modify():debug()
	self:load("journal"):modify():debug()


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