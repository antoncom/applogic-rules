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
			evname = "interface.update",
			match = { interface = "vpnpptp"}
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
			match = { interface = "vpnpptp"}
		},
		modifier = {
			["1_bash"] = [[ jsonfilter -e $.interface ]],
		}
	},


	journal = {
		input = "",
		modifier = {
			["1_skip"] = [[ if ($up_ifname == "vpnpptp" or $down_ifname == "vpnpptp") then return false else return true end ]],
			["2_func"] = [[ 
				local up = ($up_ifname == "vpnpptp") and "PPTP UP"
				local down = ($down_ifname == "vpnpptp") and "PPTP DOWN"
				local out = up or down
				return({ 
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = "Изменился статус интерфейса",
					source = "Network  (20-rule)",
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

	-- Пропускаем выполнения правила, если СИМ-карты нет в слоте
	local all_rules = rule.parent.setting.rules_list.target
	local r01_wait_timer = tonumber(all_rules["01_rule"].setting.wait_timer.output)

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
