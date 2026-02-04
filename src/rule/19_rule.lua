local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Журналирование событий Микроконтроллера",
	},
	SYS_VER = {
		note = [[ Подписываемся на команду ~0:SYS.VER ]],
		default = {},
		{
			["subscribe"] = {
				ubus = "tsmstm",
				evname = "~0:SYS.VER",
				match = {}
			},
		},
		{
			["skip"] = function (nodes)
				if not nodes.SYS_VER.command then return true else return false end
			end
		},
		{
			["journal"] = function (nodes)
				return({
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = nodes.SYS_VER.note,
					source = "STM32 (19_rule)",
					command = nodes.SYS_VER.command or "",
					response = nodes.SYS_VER.result or ""
				})
			end
		},
	},
	SIM_SEL = {
		note = [[ Подписываемся на команду ~0:SIM.SEL ]],
		default = {},
		{
			["subscribe"] = {
				ubus = "tsmstm",
				evname = "~0:SIM.SEL",
				match = {}
			},
		},
		{
			["skip"] = function (nodes)
				if not nodes.SIM_SEL.command then 
					return true 
				elseif (nodes.SIM_SEL.command == "~0:SIM.SEL=?") then
					return true
				else
					return false 
				end
			end
		},
		{
			["journal"] = function (nodes)
				return({
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = nodes.SIM_SEL.note,
					source = "STM32 (19_rule)",
					command = nodes.SIM_SEL.command or "",
					response = nodes.SIM_SEL.result or ""
				})
			end
		},
	},

	SIM_EN = {
		note = [[ Подписываемся на команду ~0:SIM.EN ]],
		default = {},
		{
			["subscribe"] = {
				ubus = "tsmstm",
				evname = "~0:SIM.EN",
				match = {}
			},
		},
		{
			["skip"] = function (nodes)
				if not nodes.SIM_EN.command then return true else return false end
			end
		},
		{
			["journal"] = function (nodes)
				return({
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = nodes.SIM_EN.note,
					source = "STM32 (19_rule)",
					command = nodes.SIM_EN.command or "",
					response = nodes.SIM_EN.result or ""
				})
			end
		},
	},

	SIM_RST = {
		note = [[ Подписываемся на команду ~0:SIM.RST ]],
		default = {},
		{
			["subscribe"] = {
				ubus = "tsmstm",
				evname = "~0:SIM.RST",
				match = {}
			},
		},
		{
			["skip"] = function (nodes)
				if not nodes.SIM_RST.command then return true else return false end
			end
		},
		{
			["journal"] = function (nodes)
				return({
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = nodes.SIM_RST.note,
					source = "STM32 (19_rule)",
					command = nodes.SIM_RST.command or "",
					response = nodes.SIM_RST.result or ""
				})
			end
		},
	},

	SIM_PWR = {
		note = [[ Подписываемся на команду ~0:SIM.PWR ]],
		default = {},
		{
			["subscribe"] = {
				ubus = "tsmstm",
				evname = "~0:SIM.PWR",
				match = {}
			},
		},
		{
			["skip"] = function (nodes)
				if not nodes.SIM_PWR.command then return true else return false end
			end
		},
		{
			["journal"] = function (nodes)
				return({
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = nodes.SIM_PWR.note,
					source = "STM32 (19_rule)",
					command = nodes.SIM_PWR.command or "",
					response = nodes.SIM_PWR.result or ""
				})
			end
		},
	},

	SIM_RSTSW = {
		note = [[ Подписываемся на команду ~0:SIM.RSTSW ]],
		default = {},
		{
			["subscribe"] = {
				ubus = "tsmstm",
				evname = "~0:SIM.RSTSW",
				match = {}
			},
		},
		{
			["skip"] = function (nodes)
				if not nodes.SIM_RSTSW.command then return true else return false end
			end
		},
		{
			["journal"] = function (nodes)
				return({
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = nodes.SIM_RSTSW.note,
					source = "STM32 (19_rule)",
					command = nodes.SIM_RSTSW.command or "",
					response = nodes.SIM_RSTSW.result or ""
				})
			end
		},
	},

	SIM_PWRSW = {
		note = [[ Подписываемся на команду ~0:SIM.PWRSW ]],
		default = {},
		{
			["subscribe"] = {
				ubus = "tsmstm",
				evname = "~0:SIM.PWRSW",
				match = {}
			},
		},
		{
			["skip"] = function (nodes)
				if not nodes.SIM_PWRSW.command then return true else return false end
			end
		},
		{
			["journal"] = function (nodes)
				return({
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = nodes.SIM_PWRSW.note,
					source = "STM32 (19_rule)",
					command = nodes.SIM_PWRSW.command or "",
					response = nodes.SIM_PWRSW.result or ""
				})
			end
		},
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
	self:follow("SYS_VER"):debug()

	self:follow("SIM_SEL"):debug()
	--self:follow("SIM_EN"):debug()
	--self:follow("SIM_RST"):debug()
	--self:follow("SIM_PWR"):debug()
	--self:follow("SIM_RSTSW"):debug()
	--self:follow("SIM_PWRSW"):debug()
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
