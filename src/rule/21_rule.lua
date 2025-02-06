local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"
local log = require "applogic.util.log"
local I18N = require "luci.i18n"

local rule = {}
local rule_setting = {
	title = {
		input = "Журналирование - статус интерфейса OpenVPN VPN",
	},
	up_ifname = {
		note = [[ Имя сетевого интерфейса, который up ]],
		input = "",
		source = {
			type = "subscribe",
			ubus = "network.interface",
			evname = "interface.update",
			match = { interface = "openvpn"}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.interface ]],
		}
	},

	down_ifname = {
		note = [[ Имя сетевого интерфейса, который down ]],
		input = "",
		source = {
			type = "subscribe",
			ubus = "network.interface",
			evname = "interface.down",
			match = { interface = "openvpn"}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.interface ]],
		}
	},


	journal = {
		input = "",
		modifier = {
			["1_skip"] = [[ if ($up_ifname == "openvpn" or $down_ifname == "openvpn") then return false else return true end ]],
			["2_func"] = [[ 
				local up = ($up_ifname == "openvpn") and "OpenVPN UP"
				local down = ($down_ifname == "openvpn") and "OpenVPN DOWN"
				local out = up or down
				return({ 
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = "Изменился статус сетевого интерфейса",
					source = "Network  (21-rule)",
					command = "subscribe network.interface",
					response = out
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
	self:load("down_ifname"):modify():debug()
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
