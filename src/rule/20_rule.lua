local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Журналирование - статус интерфейса PPTP VPN",
	},
	up_ifname = {
		note = [[ Имя сетевого интерфейса, который up ]],
		input = "",
		source = {
			type = "subscribe",
			ubus = "network.interface",
			event_name = "",
			match = { interface = "vpnpptp"}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.interface ]],
		}
	},


	previous = {
		note = [[ Отличается ли статус от предыдущего значения ]],
		input = "",
		modifier = {
			["1_skip"] = [[ return ($up_ifname ~= "vpnpptp") ]],
			["2_func"] = [[ 
				local vpnpptp_status = $vpnpptp_is_up
			]],
            ["3_save"] = [[ return $vpnpptp_is_up ]]
		}
	},

	vpnpptp_is_up = {
		note = [[ Статус интерфейса vpnpptp ]],
		input = "",
		source = {
			type = "subscribe",
			ubus = "network.interface",
			event_name = "",
			match = { interface = "vpnpptp"}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.up ]],
		}
	},
	
	journal = {
		modifier = {
			["1_skip"] = [[ if ($up_ifname == "vpnpptp" and $vpnpptp_is_up ~= $previous) then return false else return true end ]],
			["2_func"] = [[ 
				return({ 
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = "Изменился статус интерфейса [" .. $up_ifname .. "]",
					source = "Network  (20-rule)",
					command = "subscribe network.interface",
					response = $vpnpptp_is_up
				}) 
			]],
			["3_store-db"] = {
				param_list = { "journal" }	
			},
		}
	}
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
-- Alternatively, you may run debug via shell like this "applogic 05_rule title sim_id" (use 5 variable names maximum)
function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end

	self:load("title"):modify():debug()
	self:load("up_ifname"):modify():debug()
	self:load("previous"):modify():debug()
	self:load("vpnpptp_is_up"):modify():debug()
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
