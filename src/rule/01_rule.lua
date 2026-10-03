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
		{
			["break"] = function (nodes)
				local last_switch_time = nodes.slotinfo.last_switch_time or 0
				if ((os.time() - last_switch_time) < 5) then return true else return false end
			end
		},
	},

	sim_found = {
		note = [[ Сим-карта в слоте? "true" / "false" / "" (ещё неизвестно) ]],

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
			["websocket"] = function(nodes)
				return({
					sim_id = nodes.slotinfo.slot,
					timeout = nodes.timeout and nodes.timeout.inited or 600,
					wait_timer = nodes.timeout and nodes.timeout.value or 600,
					sim_ready = nodes.sim_found.value
				})
			end
		},
		{	-- Прерываем правило, если симка в слоте ИЛИ состояние ещё неизвестно
			-- (пустое значение бывает при старте tsmodem и сразу после sim_slot_off).
			-- Отсчёт ожидания идёт только при явном "false" / "failure".
			-- [break] стирает таймер узла timeout, поэтому при следующем пропадании
			-- карты отсчёт начинается заново.
			["break"] = function (nodes)
				local last_switch_time = nodes.slotinfo.last_switch_time or 0
				if ((os.time() - last_switch_time) < 5) then return true end
				local v = nodes.sim_found.value
				return (v == "true" or v == "" or v == nil)
			end
		},
	},

	timeout = {
		note = [[ Таймер ожидания сим-карты в пустом слоте. Поиск карты ведёт сам tsmodem. ]],
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
		{	-- Пока отсчёт не подошёл к концу, слот не переключаем
			["break"] = function (nodes)
				return ((tonumber(nodes.timeout.value) or 0) > 5)
			end
		},
	},

	switch = {
		note = [[ Переключить слот Сим-карт  ]],
		{
			["func"] = function (nodes)
				local new_slotid = nil
				local current_slotid = nodes.slotinfo.slot
				if(current_slotid == "0") then new_slotid = "1" end
				if(current_slotid == "1") then new_slotid = "0" end
				return new_slotid
			end
		},
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmslot",
					method = "switch",
					params = { slotid = nodes.switch },
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

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end


	self:follow("title"):debug()
	self:follow("slotinfo"):debug()			-- Пропускаем все узлы ниже, если слот переключили менее 5 сек назад
	self:follow("sim_found"):debug()		-- Пропускаем все узлы ниже, если симка найдена или состояние неизвестно
	self:follow("timeout"):debug()			-- Сколько ждать симку в пустом слоте (из конфига); пока ждём - прерываем правило
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