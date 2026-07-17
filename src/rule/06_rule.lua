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
				if ((os.time() - last_switch_time) < 60) then return true end
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
		},
		{	-- Если симка не в слоте, то пропускаем дальнейшую обработку правила
			["break"] = function (nodes)
				local last_switch_time = nodes.slotinfo.last_switch_time or 0
				if ((os.time() - last_switch_time) < 60) then return true end
				return (nodes.sim_found.value ~= "true")
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

	netmode = {
		note = [[ Режим сети 2G/3G/4G ]],
		{
			["load-ubus"] = function(nodes)
				return {
					object = "tsmodem.driver",
					method = "netmode",
					params = {},
				}
			end
		},
		{
			["websocket"] = function(nodes)
				return {
					sim_id = nodes.slotinfo.slot,
					netmode = nodes.netmode.value
				}
			end
		},
	},

	LED1_mode = {
        note = [[ Режим мигания светодиода LED1 ]],

		{
            ["func"] = function (nodes)
                local no_blinking_mode = "mode0"

				local mode_1 = { scale = 25, blinking_mode = "mode1" }
                local mode_2 = { scale = 50, blinking_mode = "mode2" }
                local mode_3 = { scale = 75, blinking_mode = "mode3" }
                local mode_4 = { scale = 100, blinking_mode = "mode4" }
				local signal = tonumber(nodes.signal.value) or 0

				if (nodes.sim_found.value ~= "true") then return no_blinking_mode
					elseif (signal == 0) then return no_blinking_mode
					elseif (signal <= mode_1.scale) then return mode_1.blinking_mode
	                elseif (signal > mode_1.scale and signal <= mode_2.scale) then return mode_2.blinking_mode
	                elseif (signal > mode_2.scale and signal <= mode_3.scale) then return mode_3.blinking_mode
	                elseif (signal > mode_3.scale and signal <= mode_4.scale) then return mode_4.blinking_mode
					else return no_blinking_mode
                end
            end
        },
    },

	LED1_mode_save = {
		note = [[ Режим мигания светодиода LED1 (сохранение режима в текущей и прошлой итерациях) ]],

		{
			["save"] = function(nodes)
				local prev = nil
				if nodes.LED1_mode_save and nodes.LED1_mode_save.current then
					prev = nodes.LED1_mode_save.current
				end
				return { current = nodes.LED1_mode, prev = prev }
			end
		}
	},

	update_led_signal_mode = {
		note = [[ Обновление режима мигания SIGNAL светодиода ]],

		{
			["skip"] = function (nodes)
				local current_mode = nodes.LED1_mode_save.current
				local prev_mode = nodes.LED1_mode_save.prev
				return prev_mode == current_mode
			end
		},
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmsignal",
					method = "set_signal_mode",
					params = { mode = nodes.LED1_mode }
				}
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
	self:follow("netmode"):debug()
	self:follow("LED1_mode"):debug()
	self:follow("LED1_mode_save"):debug()
	self:follow("update_led_signal_mode"):debug()
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
