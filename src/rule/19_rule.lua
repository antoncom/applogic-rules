local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Журналирование событий GPIO (ToDO: доработать под БР-02)",
	},

	SIM_SEL = {
		note = [[ Подписываемся на команду "SIM_SEL" (смена слота) ]],
		default = {},
		{
			["subscribe"] = {
				ubus = "tsmslot",
				evname = "SIM_SEL",
				match = {}
			},
		},
		{
			["skip"] = function (nodes)
				if not nodes.SIM_SEL.command then 
					return true 
				elseif (nodes.SIM_SEL.command == "SIM_SEL") then
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
					source = "GPIO (19_rule)",
					command = nodes.SIM_SEL.command or "",
					response = nodes.SIM_SEL.result or ""
				})
			end
		},
	},

	SIM_EN = {
		note = [[ Подписываемся на команду SIM_EN (вкл/выкл питания модема) ]],
		default = {},
		{
			["subscribe"] = {
				ubus = "tsmslot",
				evname = "SIM_EN",
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
					source = "GPIO (19_rule)",
					command = nodes.SIM_EN.command or "",
					response = nodes.SIM_EN.result or ""
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

	self:follow("SIM_SEL"):debug()
	self:follow("SIM_EN"):debug()
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
