local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Журналирование - статус интерфейса MODEM",
	},
	up_ifname = {
		note = [[ Имя сетевого интерфейса, который up ]],
		input = "",
		-- source = {
		-- 	type = "subscribe",
		-- 	ubus = "network.interface",
		-- 	evname = "interface.update",
		-- 	match = { interface = "modem"}
		-- },
		-- modifier = {
		-- 	-- ["1_bash"] = [[ jsonfilter -e $.interface ]],
		-- 	["1_lua-func"] = function (vars)
		-- 		local lua_table = luci.jsonc.parse(vars.subtotal) or {}
		-- 		return lua_table.interface or ""
		-- 	end,
		-- }

		{
			["subscribe"] = {
				ubus = "network.interface",
				evname = "interface.update",
				match = { interface = "modem"}
			},
		},
		{
			["func"] = function (vars)
				local lua_table = luci.jsonc.parse(vars.up_ifname) or {}
				return lua_table.interface or ""
			end,
		}
	},

	down_ifname = {
		note = [[ Имя сетевого интерфейса, который down ]],
		input = "",
		-- source = {
		-- 	type = "subscribe",
		-- 	ubus = "network.interface",
		-- 	evname = "interface.down",
		-- 	match = { interface = "modem"}
		-- },
		-- modifier = {
		-- 	-- ["1_bash"] = [[ jsonfilter -e $.interface ]],
		-- 	["1_lua-func"] = function (vars)
		-- 		local lua_table = luci.jsonc.parse(vars.subtotal) or {}
		-- 		return lua_table.interface or ""
		-- 	end,
		-- }

		{
			["subscribe"] = {
				ubus = "network.interface",
				evname = "interface.down",
				match = { interface = "modem"}
			}
		},
		{
			["func"] = function (vars)
				local lua_table = luci.jsonc.parse(vars.down_ifname) or {}
				return lua_table.interface or ""
			end,
		}
	},


	journal = {
		input = "",
		-- modifier = {
		-- 	["1_skip"] = [[ if ($up_ifname == "modem" or $down_ifname == "modem") then return false else return true end ]],
		-- 	["2_func"] = [[ 
		-- 		local up = ($up_ifname == "modem") and "Modem UP"
		-- 		local down = ($down_ifname == "modem") and "Modem DOWN"
		-- 		local out = up or down
		-- 		return({ 
		-- 			datetime = os.date("%Y-%m-%d %H:%M:%S"),
		-- 			name = "Изменился статус интерфейса сетевого интерфейса",
		-- 			source = "Network  (19-rule)",
		-- 			command = "subscribe network.interface",
		-- 			response = out
		-- 		}) 
		-- 	]],
		-- 	["3_store-db"] = {
		-- 		param_list = { "journal" }	
		-- 	},
		-- }

		{
			["skip"] = function (vars)
				if (vars.up_ifname == "modem" or vars.down_ifname == "modem") then return false else return true end
			end
		},
		{
			["func"] = function (vars)
				local up = (vars.up_ifname == "modem") and "Modem UP"
				local down = (vars.down_ifname == "modem") and "Modem DOWN"
				local out = up or down
				return({
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = "Изменился статус интерфейса сетевого интерфейса",
					source = "Network  (19-rule)",
					command = "subscribe network.interface",
					response = out
				})
			end
		},
		{
			["store-db"] = {
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

	-- Пропускаем выполнние правила, если модуль tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end


	local all_rules = rule.parent.setting.rules_list.target

	-- Пропускаем выполнения правила, если СИМ-карты нет в слоте
	local r01_wait_timer = tonumber(all_rules["01_rule"].setting.wait_timer.output)
	if (r01_wait_timer and r01_wait_timer > 0) then 
		if rule.debug_mode.enabled then print("------ 19_rule SKIPPED as r01_wait_timer > 0 -----") end
		return
	end


	self:follow("title"):debug()
	self:follow("up_ifname"):debug()
	self:follow("down_ifname"):debug()
    self:follow("journal"):debug()
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
