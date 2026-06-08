local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"

local rule = {}
local rule_setting = {
	title = {
		input = "Мигание светодиода LED1 - уровень сигнала",
	},
	slotinfo = {
		note = [[ Данные о слотах Сим ]],
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmslot",
					method = "info",
					params = {},
				}
			end
		},
		{	-- Если идёт процесс переключения, то пропускаем дальнейшую обработку правила
			["break"] = function (nodes)
				local last_switch_time = nodes.slotinfo.last_switch_time or 0
				if ((os.time() - last_switch_time) < 10) then return true end
			end
		},
	},

	sim_found = {
		note = [[ Сим-карта в слоте? "true" / "false" ]],
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmodem.driver",
					method = "cpin",
					params = {},
				}
			end
		}
	},

	signal = {
		note = [[ Уровень сигнала сотового оператора, %. ]],
		{
			["load-ubus"] = function(nodes)
				return {
					object = "tsmodem.driver",
					method = "signal",
					params = {},
				}
			end
		}
	},

    LED1_mode = {
        note = [[ Режим мигания светодиода LED1 ]],

		{
            ["func"] = function (nodes)
                local no_blinking = "v0"
                local mode_1 = { scale = 25, blinking = "f200,800" }
                local mode_2 = { scale = 50, blinking = "f200,200,200,800" }
                local mode_3 = { scale = 75, blinking = "f200,200,200,200,200,800" }
                local mode_4 = { scale = 100, blinking = "f200,200,200,200,200,200,200,800" }
				local signal = tonumber(nodes.signal.value) or 0
				if (nodes.sim_found.value ~= "true") then return no_blinking
					elseif (signal == 0) then return no_blinking
					elseif (signal <= mode_1.scale) then return mode_1.blinking
	                elseif (signal > mode_1.scale and signal <= mode_2.scale) then return mode_2.blinking
	                elseif (signal > mode_2.scale and signal <= mode_3.scale) then return mode_3.blinking
	                elseif (signal > mode_3.scale and signal <= mode_4.scale) then return mode_4.blinking
					else return no_blinking
                end
            end
        },
    },

	send_stm_at = {
		note = [[ Отправка настроек светодиода LED1 ]],
		{
            ["skip"] = function (nodes)
                return (nodes.LED1_mode == nodes.previous)
            end
        },
		{
			-- TODO: переделать мигание светодиодов
			-- ранее это делалось через STM32
			-- теперь надо сджелать через GPIO
			-- быстрее всего подойдёт сервис Tsmslot
			-- =====================================
			["load-ubus"] = function (nodes)
				return {
					object = "tsmstm",
					method = "send",
					params = { command = "~0:LED.1=" .. nodes.LED1_mode },
				}
			end
		}
    },

	previous = {
		note = [[ Режим мигания светодиода LED1 (на предыдущей итерации). ]],

		{
			["func"] = function (nodes)
				return nodes.LED1_mode
			end,
		},
		{
			["save"] = function(nodes)
				return nodes.previous
			end
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

	local all_rules = rule.parent.setting.rules_list.target

	-- Пропускаем выполнения правила, если СИМ-карты нет в слоте
	--[[
	local r01_wait_timer = tonumber(all_rules["01_rule"].setting.wait_timer.output)
	if (r01_wait_timer and r01_wait_timer > 0) then
		--if rule.debug_mode.enabled then print("------ 06_rule SKIPPED as r01_wait_timer > 0 -----") end
		return
	end
]]--
	self:follow("title"):debug()
	self:follow("slotinfo"):debug()		
	self:follow("sim_found"):debug()			
    self:follow("signal"):debug()
	self:follow("LED1_mode"):debug()
	self:follow("send_stm_at"):debug()
	self:follow("previous"):debug()
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
