local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило открывания/закрывания шторки 'Переключение Сим' в веб-интерфейсе",
	},

	show_cover = {
		note = [[ Показываем заставку "Идёт переключение слотов" ]],
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmstm",
					method = "info",
					params = {},
				}
			end
		},
		{	
			["skip"] = function (nodes)
				local last_switch_time = nodes.show_cover.last_switch_time or 0
				if ((os.time() - last_switch_time) > 15) then return true else return false end
			end
		},
		{
			["ui-update"] = function(nodes)
				return({
					simid = nodes.show_cover.slot,
					switching = "true"
				})
			end
		},
		{
			["break"] = function(nodes)
				return true
			end
		},
	},

	hide_cover = {
		note = [[ Скрываем заставку "Идёт переключение слотов" ]],
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmstm",
					method = "info",
					params = {},
				}
			end
		},
		{	
			["skip"] = function (nodes)
				local last_switch_time = nodes.show_cover.last_switch_time or 0
				if ((os.time() - last_switch_time) < 15) then return true else return false end
			end
		},
		{
			["ui-update"] = function(nodes)
				return({
					simid = nodes.show_cover.slot,
					switching = "false"
				})
			end
		},
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

	local overview = {
		["sim_id"] = { ["red"] = [[ return($sim_id ~= "0" and $sim_id ~= "1") ]] },
		["switching"] = { ["yellow"] = [[ return($switching ~= "false") ]] },
	}

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end

	self:follow("title"):debug() -- Use debug(ONLY) to check the var only
	self:follow("show_cover"):debug()
	self:follow("hide_cover"):debug()
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
