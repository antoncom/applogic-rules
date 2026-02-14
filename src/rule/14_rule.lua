local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.operator.rule_init"



local rule = {}
local rule_setting = {
	title = {
		input = "Автоопределение провайдера",
	},

	slotinfo = {
		note = [[ Данные о слотах Сим ]],
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmstm",
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
		},
		{
			["ui-update"] = function(nodes)
				if(nodes.sim_found.value ~= "true") then
					return({
						sim_id = tostring(nodes.slotinfo.slot),
						provider_name = ""
					})
				end
			end
		},
		{	-- Если нет симки в слоте, то пропускаем дальнейшую обработку правила
			["break"] = function (nodes)
				return (nodes.sim_found.value ~= "true")
			end
		}
	},

	provider_setting = {
		note = [[ Определить текущую настройку - идентификатор провайдера ]],

		{
			["load-ubus"] = function (nodes)
				return {
					object = "uci",
					method = "get",
					params = {
						config = "tsmodem",
						section = "sim_" .. tostring(nodes.slotinfo.slot),
						option = nil,
					},
				}
			end
		}
	},

	provider_detected = {
		note = [[ Идентификатор провайдера после автоопределения ]],
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmodem.driver",
					method = "provider_name",
					params = {},
				}
			end
		},
		{
			["break"] = function (nodes)
				return (nodes.provider_detected.value == "")
			end
		},
		{
			["ui-update"] = function(nodes)
				return({
					sim_id = tostring(nodes.slotinfo.slot),
					provider_name = nodes.provider_detected.value
				})
			end
		},
		{
			["skip"] = function (nodes)
				local CHANGED = (nodes.provider_detected_before and nodes.provider_detected_before.value and nodes.provider_detected and nodes.provider_detected.value == nodes.provider_detected_before.value and #nodes.provider_detected.value > 0)
				return CHANGED or false
			end
		},
		{
			["journal"] = function (nodes)
				return({
					name = "Автоопределение провайдера в слоте SIM-" .. (tonumber(nodes.slotinfo.slot)+1),
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					source = "GSM-модем  [14_rule]",
					command = "AT+COPS?",
					response = nodes.provider_detected.value
				})
			end
		},

	},
	provider_detected_before = {
		note = [[ Идентификатор провайдера на педыдущей итерации ]],
		{
			["save"] = function (nodes)
				return(nodes.provider_detected)
			end
		},
	}
}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
-- Alternatively, you may run debug via shell like this "applogic 01_rule title sim_id" (use 5 variable names maximum)
function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	-- These variables are included into debug overview (run "applogic debug" to get all rules overview)
	-- Green, Yellow and Red are measure of importance for Application logic
	-- Green is for timers and some passive variables,
	-- Yellow is for that vars which switches logic - affects to normal application behavior
	-- Red is for some extraordinal application behavior, like watchdog, etc.
	local overview = {
		["reset_modem"] = { ["yellow"] = [[ return ($reset_modem == "true") ]] },
		["do_switch"] = { ["yellow"] = [[ return ($do_switch == "true") ]] },
		["sim_found"] = { ["yellow"] = [[ return ($sim_found == "false" or $sim_found == "*") ]] },
		["reset_timer"] = { ["yellow"] = [[ return (tonumber($reset_timer) and tonumber($reset_timer) > 0) ]] },
		["wait_timer"] = { ["yellow"] = [[ return (tonumber($wait_timer) and tonumber($wait_timer) > 0) ]] },
	}

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end


	self:follow("title"):debug()
	self:follow("slotinfo"):debug()			-- Пропускаем все узлы ниже, если прошло не более 20 сек после начала переключения слотов
	self:follow("sim_found"):debug()		-- Пропускаем все узлы ниже, если симка найдена в слоте
	self:follow("provider_setting"):debug()	-- Получаем текущие настройки провайдера из конфига
	self:follow("provider_detected"):debug()-- Определяем какй провайдер определился на Сим-карте
	self:follow("provider_detected_before"):debug()-- Сохраняем значение провайдера для сравнения на след.итерации

	
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
