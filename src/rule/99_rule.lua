local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило отображения процесса 'Переключение Сим' в веб-интерфейсе",
	},

	show_cover = {																		-- создаём логический узел "show_cover"
		note = [[ Показываем заставку "Идёт переключение слотов" ]],
		{
			["load-ubus"] = function (nodes)											-- оператор [load-ubus] получает состояние
				return {																-- слотов от Микроконтроллера
					object = "tsmslot",
					method = "info",
					params = {},
				}
			end
		},
		{	
			["skip"] = function (nodes)													-- если в данный момент происходит 
				local last_switch_time = nodes.show_cover.last_switch_time		 		-- переключение слотов, то оператор [skip]
				if ((os.time() - last_switch_time) > 15) then 							-- отменяет обработку следующих за ним операторов
					return true else return false 										-- узла, таких как: [ui-update] и [break]
				end
			end
		},
		{
			["websocket"] = function(nodes)												-- если же имеет место переключение слотов, то
				return({																-- отправляем в веб-интерфейс switching="true"
					simid = nodes.show_cover.slot,										-- при помощи оператора [ui-update]								
					switching = "true"													
				})
			end
		},
		{
			["break"] = function(nodes)													-- и прерываем дальнейшую обработку данного
				return true 															-- правила оператором [break],
			end 																		-- так как в этом нет необходимости
		},
	},

	hide_cover = {																		-- создаём логический узел "hide_cover"
		note = [[ Скрываем заставку "Идёт переключение слотов" ]],
		{
			["load-ubus"] = function (nodes)											-- оператор [load-ubus] получает состояние
				return {																-- слотов от Микроконтроллера
					object = "tsmslot",
					method = "info",
					params = {},
				}
			end
		},
		{	
			["skip"] = function (nodes)													-- если переключение слотов окончено, то 
				local last_switch_time = nodes.show_cover.last_switch_time				-- оператор [skip] возвращает "false"
				if ((os.time() - last_switch_time) < 15) then 
					return true else return false 
				end
			end
		},
		{
			["websocket"] = function(nodes)												-- следовательно, если [skip]=false,
				return({																-- то оператор [ui-updte] не отменяется,
					simid = nodes.show_cover.slot,										-- а выполняется, посылая в веб-интерфейс
					switching = "false"													-- значение switching="false"
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
