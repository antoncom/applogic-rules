local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"



local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения если нет Cим-карты в слоте",
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
		},
		{
			["ui-update"] = function(nodes)
				return({
					sim_id = nodes.slotinfo.slot,
					timeout = nodes.timeout and nodes.timeout.inited or 600,
					wait_timer = nodes.timeout and nodes.timeout.value or 600,
					sim_ready = nodes.sim_found.value
				})
			end
		},
		{	-- Если симка в слоте, то пропускаем дальнейшую обработку правила
			["break"] = function (nodes)
				local last_switch_time = nodes.slotinfo.last_switch_time or 0
				if ((os.time() - last_switch_time) < 20) then return true end
				return (nodes.sim_found.value == "true")
			end
		}
	},

	timeout = {
		note = [[ Таймер ожидания при поиске сим-карты  ]],
		["default"] = 15,
		{	-- Загружаем значение таймера из конфига
			["load-ubus"] = function (nodes)
				return {
					object = "uci",
					method = "get",
					params = {
						config = "tsmodem",
						section = "sim_" .. tostring(nodes.slotinfo.slot),
						option = "timeout_sim_absent",
					}
				}
			end
		},
		{   -- Запускаем таймер
			["timeout"] = function(nodes)
				return tonumber(nodes.timeout.value)
			end
		},
	},



	reset = {
		note = [[ Сбросить модем для поиска Sim в слоте ]],
		default = "",
		{
			["skip"] = function (nodes)
				local notyet_found = (nodes.sim_found.value ~= "true")
				local time_isout = (nodes.timeout.value == 0)

				local stop_resetting_if_timeout = (notyet_found and time_isout)
				return stop_resetting_if_timeout
			end
		},
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmslot",
					method = "reset",
					params = {},
				}
			end
		},
		{
			["journal"] = function (nodes)
				return({
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = 'Сброс питания Sim-слота',
					source = "Network (01_rule)",
					command = "ubus call tsmslot reset",
					response = "started"
				})
			end
		},
		{
			["frozen"] = function (nodes)
				return 20
			end
		},
		{
			["break"] = function (nodes)
				if nodes.timeout.value > 0 then
					return true
				else
					return false
				end
			end
		}
	},
	

	switch = {
		note = [[ Переключить слот Сим-карт  ]],
		{
			["func"] = function (nodes)
				local new_slotid = nil
				local current_slotid = nodes.slotinfo.slot
				if(current_slotid == 0) then new_slotid = "1" else new_slotid = "0" end
				return new_slotid
			end
		},
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmslot",
					method = "switch",
					params = { simid = nodes.switch },
					cached = "no",
				}
			end
		},
		{
			["journal"] = function (nodes)
				return({
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = 'Переключение Sim-слота (симка не найдена)',
					source = "Network (01_rule)",
					command = "ubus call tsmslot switch",
					response = "started"
				})
			end
		},
		{
			["frozen"] = function (nodes)
				return 30
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
	self:follow("slotinfo"):debug()				-- Пропускаем все узлы ниже, если прошло не более 20 сек после начала переключения слотов
	self:follow("sim_found"):debug()		-- Пропускаем все узлы ниже, если симка найдена в слоте
	self:follow("timeout"):debug()			-- Сколько ждать симку в слоте (из конфига)
	self:follow("reset"):debug()			-- Ресеттим модем, таймаут не превышен. Замораживаем узел на 20 сек.,
											-- а в это время узел "sim_found" ищет симку.
	self:follow("switch"):debug()			-- Переключаем слот, если вышел таймаут
	
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
