local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило журналирования статуса регистрации в сети",
	},

	event_datetime = {
		note = [[ Дата события. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "reg",
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
			method = "reg",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.unread ]],
		}
	},

	event_reg = {
		note = [[ Статус регистрации Сим-карты в сети. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",	-- This is UBUS OBJECT name. Run in the shell "ubus list | grep tsmodem" to see all objects.
			method = "reg",				-- This is UBUS METHOD name. Run in the shell "ubus -v list tsmodem driver" to see all nethods.
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
		}
	},


	journal = {
		note = [[ Отправка данных в Журнал событий в Web-интерфейсе. ]],
		modifier = {
			["1_skip"] = [[ local EVENT_NEW = ($event_is_new == "true")
							local NOT_EMPTY = ($event_reg ~= "")
							if not (EVENT_NEW and NOT_EMPTY) then return true else return false end
						 ]],
			["2_func"] = [[return({
					datetime = $event_datetime,
					name = "Изменился статус регистрации в сети",
					source = "Модем",
					command = "AT+CREG?",
					response = $event_reg
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
	self:load("event_reg"):modify():debug()
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
