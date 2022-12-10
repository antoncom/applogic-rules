local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"


local rule = {}
local rule_setting = {
	title = {
		input = "Индикация названия провайдера сотовой сети по данным автоопределения",
	},

	event_datetime = {
		note = [[ Дата события. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "provider_name",
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
			method = "provider_name",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.unread ]],
		}
	},

	sim_id = {
		note = [[ Идентификатор Сим-карты, 0/1 ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",
			method = "sim",
			params = {},
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.value ]],
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

	provider_name = {
		note = [[ Наименование провайдера. ]],
		source = {
			type = "ubus",
			object = "tsmodem.driver",	-- This is UBUS OBJECT name. Run in the shell "ubus list | grep tsmodem" to see all objects.
			method = "provider_name",				-- This is UBUS METHOD name. Run in the shell "ubus -v list tsmodem driver" to see all nethods.
			params = {},
		},
		modifier = {
			["1_skip"] = [[
				local REG_OK = 	( $network_registration == "1" )
				local NO_NAME = ( $provider_name == "" )
				return ( not REG_OK or NO_NAME )
			]],
			["2_bash"] = [[ jsonfilter -e $.value ]],
			["3_ui-update"] = {
				param_list = { "provider_name", "sim_id" }
			}
		}
	},

	journal = {
		note = [[ Отправка данных в Журнал событий в Web-интерфейсе. ]],
		modifier = {
			["1_skip"] = [[ local EVENT_NEW = ($event_is_new == "true")
							local NOT_EMPTY = ($provider_name ~= "")
							if not (EVENT_NEW and NOT_EMPTY) then return true else return false end
						 ]],
			["2_func"] = [[return({
					datetime = $event_datetime,
					name = "Идентифицирован GSM-провайдер",
					source = "Модем",
					command = "+NITZ",
					response = $provider_name
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
	debug_mode.level = "INFO"
	local ONLY = rule.debug_mode.level


	self:load("title"):modify():debug()
	self:load("event_datetime"):modify():debug()
	self:load("event_is_new"):modify():debug()
	self:load("sim_id"):modify():debug()
	self:load("provider_name"):modify():debug(ONLY)
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
