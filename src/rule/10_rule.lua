local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило журналирования статуса подключения порта /dev/ttyUSB2",
	},

	event_datetime = {
		note = [[ Дата события. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "usb",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.time ]],
			["2_func"] = [[ if tonumber($event_datetime) then return(os.date("%Y-%m-%d %H:%M:%S", $event_datetime)) else return "" end ]]
		}
	},

	event_is_new = {
		note = [[ Признак новых данных. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "usb",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.unread ]],
		}
	},

	event_usb_value = {
		note = [[ Статус подключения модема к порту ttyUSB2. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "usb",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},

	event_usb_command = {
		note = [[ Команда подключения/отключения модема к порту ttyUSB2. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "usb",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.command ]],
		}
	},


	journal = {
		note = [[ Отправка данных в Журнал событий в Web-интерфейсе. ]],
		modifier = {
			["1_skip"] = [[ local NEW_EVENT = ($event_is_new == "true")
							if not NEW_EVENT then return true else return false end
						 ]],
			["2_func"] = [[ return({
					datetime = $event_datetime,
					name = "Состояние порта /dev/ttyUSB2 изменилось",
					source = "Модем",
					command = $event_usb_command,
					response = $event_usb_value
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
	self:load("event_is_new"):modify():debug()
	self:load("event_usb_value"):modify():debug()
	self:load("event_usb_command"):modify():debug()
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
