local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Checking the subscription feature..",
	},

	sms_sent_ok = {
		note = [[ The variable is loaded on subscription ]],
		source = {
			type = "subscribe",
			ubus = "tsmodem.driver",
			event_name = "SMS-SENT-OK",
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.payload.answer ]]
		}
	},

	sms_sent_error = {
		note = [[ The variable is loaded on subscription ]],
		source = {
			type = "subscribe",
			ubus = "tsmodem.driver",
			event_name = "SMS-SENT-ERROR",
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.payload.answer ]]
		}
	},

	event_datetime = {
		modifier = {
			["1_func"] = 'return(os.date("%Y-%m-%d %H:%M:%S", tonumber(os.time())))'
		}
	},

	journal = {
		modifier = {
			["1_skip"] = [[ if ($sms_sent_ok == "" or $sms_sent_error == "") then return true else return false end ]],
			["2_func"] = [[
				if ($sms_sent_ok ~= "") then
					return({
						datetime = $event_datetime,
						name = "Received SMS command",
						source = "Modem  (18-rule)",
						command = "Sending SMS..",
						response = $sms_sent_ok
					})
				elseif($sms_sent_error ~= "") then
					return({
						datetime = $event_datetime,
						name = "Received SMS command",
						source = "Modem  (18-rule)",
						command = "Sending SMS..",
						response = $sms_sent_error
					})
				end
				]],
                
			["3_ui-update"] = {
				param_list = { "journal" }
			},
		}
	},

}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
-- Alternatively, you may run debug via shell like this "applogic 01_rule title sim_id" (use 5 variable names maximum)
function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	-- if rule.parent.state.mode == "stop" then return end

	self:load("title"):modify():debug() 	-- Use debug(ONLY) to check the var only
	self:load("sms_sent_ok"):modify():debug()	-- Use "overview" to include the variable to the all rules overview report in debug mode
	self:load("sms_sent_error"):modify():debug()	-- Use "overview" to include the variable to the all rules overview report in debug mode
	self:load("event_datetime"):modify():debug()
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
