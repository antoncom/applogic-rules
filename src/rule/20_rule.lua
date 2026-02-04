local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Журналирование - статус интерфейса MODEM",
	},
	up_ifname = {
		note = [[ Имя сетевого интерфейса, который up ]],
		default = "",

		{
			["subscribe"] = {
				ubus = "network.interface",
				evname = "interface.update",
				match = { interface = "modem"}
			},
		},
	 	{
			["skip"] = function (nodes)
				if not nodes.up_ifname.interface then return true else return false end
			end
	 	},
		{
			["journal"] = function (nodes)
				return({
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = 'Сетевой интерфейс "Modem"',
					source = "Network (20_rule)",
					command = "ubus subscribe",
					response = (nodes.up_ifname.up and "UP") or (nodes.up_ifname.up or "DOWN")
				})
			end
		},
		{
			["frozen"] = function (nodes) return 5 end
		}
	},

	down_ifname = {
		note = [[ Имя сетевого интерфейса, который down ]],
		default = "",

		{
			["subscribe"] = {
				ubus = "network.interface",
				evname = "interface.down",
				match = { interface = "modem"}
			},
		},
	 	{
			["skip"] = function (nodes)
				if not nodes.down_ifname.interface then return true else return false end
			end
	 	},
		{
			["journal"] = function (nodes)
				return({
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = 'Сетевой интерфейс "Modem"',
					source = "Network (20_rule)",
					command = "ubus subscribe",
					response = (nodes.down_ifname.up and "UP") or (nodes.down_ifname.up or "DOWN")
				})
			end
		},
		{
			["frozen"] = function (nodes) return 5 end
		}
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

	-- Пропускаем выполнние правила, если модуль tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end


	local all_rules = rule.parent.setting.rules_list.target

	-- -- Пропускаем выполнения правила, если СИМ-карты нет в слоте
	-- local r01_wait_timer = tonumber(all_rules["01_rule"].setting.wait_timer.output)
	-- if (r01_wait_timer and r01_wait_timer > 0) then 
	-- 	if rule.debug_mode.enabled then print("------ 19_rule SKIPPED as r01_wait_timer > 0 -----") end
	-- 	return
	-- end


	self:follow("title"):debug()
	self:follow("up_ifname"):debug()
	self:follow("down_ifname"):debug()
end


local metatable = {
    __call = function(table, parent)
        local rule_init_table = rule_init(table, rule_setting, parent)
        rule_init_table:make()
        return rule_init_table
    end
}
setmetatable(rule, metatable)
return rule