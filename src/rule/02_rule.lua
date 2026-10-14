local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"

local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения Cим-карты при отсутствии регистрации в сети",
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
		{	-- Первые 5 сек после переключения слота правило не работает (как в 01_rule).
			-- [break] стирает таймер узла timeout: отсчёт из старого слота в новый не переносится.
			["break"] = function (nodes)
				local last_switch_time = nodes.slotinfo.last_switch_time or 0
				return ((os.time() - last_switch_time) < 5)
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
		{	-- Без карты регистрации быть не может: пустым слотом занимается 01_rule.
			-- Отсчёт timeout_reg идёт только пока карта в слоте ("true").
			["break"] = function (nodes)
				return (nodes.sim_found.value ~= "true")
			end
		},
	},

	network_registration = {
		note = [[ Статус регистрации Сим-карты в сети -1..9. ]],
		{
			["load-ubus"] = function(nodes)
				return {
					object = "tsmodem.driver",
					method = "reg",
					params = {},
				}
			end
		},
		{
			["func"] = function (nodes)
				return nodes.network_registration.value
			end
		},
		{
			["websocket"] = function(nodes)
				return({
					sim_id = tostring(nodes.slotinfo.slot),
					timeout = nodes.timeout and nodes.timeout.inited or "60",
					wait_timer = nodes.timeout and tostring(nodes.timeout.value) or "60",
					network_registration = tostring(nodes.network_registration)
				})
			end
		},
		{	-- Зарегистрирована: "1" - домашняя сеть, "5" - роуминг.
			-- Если уходить с роуминговой карты нужно намеренно, уберите проверку на "5".
			["break"] = function(nodes)
				local r = nodes.network_registration
				return (r == "1" or r == "5")
			end
		},
	},

	timeout = {
		note = [[ Таймаут отсутствия регистрации в сети.  ]],
		{	-- Загружаем значение таймера из конфига
			["load-ubus"] = function (nodes)
				return {
					object = "uci",
					method = "get",
					params = {
						config = "tsmodem",
						section = "sim_" .. tostring(nodes.slotinfo.slot),
						option = "timeout_reg",
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


	switch = {
		note = [[ Переключить слот Сим-карт  ]],
		{
			["skip"] = function (nodes)
				local stil_wait = (nodes.timeout.value > 5)
				return stil_wait
			end
		},
		{
			["load-ubus"] = function (nodes)
				local new_slotid = nil
				local current_slotid = nodes.slotinfo.slot
				if(current_slotid == "0") then new_slotid = "1" end
				if(current_slotid == "1") then new_slotid = "0" end
				return {
					object = "tsmslot",
					method = "switch",
					params = { slotid = new_slotid },
					cached = "no",
				}
			end
		},
		{
			["journal"] = function (nodes)
				return({
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = 'Переключение Sim-слота (нет регистрации)',
					source = "Network (02_rule)",
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

	local overview = {
		-- Жёлтый: нет регистрации ("1" - домашняя сеть, "5" - роуминг) - идёт отсчёт timeout_reg.
		-- Условие то же, что в [break] узла network_registration.
		-- RESULT: код регистрации -1..9; "-" если значения нет.
		["network_registration"] = { ["yellow"] = function(nodes)
				local r = nodes.network_registration
				if type(r) ~= "string" and type(r) ~= "number" then r = nil end
				local not_registered = not (r == "1" or r == "5")
				return not_registered, ((r == nil or r == "") and "-" or tostring(r))
			end
		},
		-- Красный: слот переключается. Пока [skip] ждёт таймаут, значение узла пустое,
		-- после переключения [frozen] держит его 30 сек.
		-- RESULT: "switched" или сколько секунд осталось ждать "wait 25s".
		["switch"] = { ["red"] = function(nodes)
				local switch = nodes.switch
				local switched = (switch ~= nil and switch ~= "")
				if switched then return true, "switched" end
				local timer = type(nodes.timeout) == "table" and tonumber(nodes.timeout.value)
				return false, (timer and ("wait " .. timer .. "s") or "-")
			end
		},
	}

	self:follow("title"):debug()
	self:follow("slotinfo"):debug()			-- Пропускаем все узлы ниже первые 5 сек после переключения слотов
	self:follow("sim_found"):debug()		-- Пропускаем все узлы ниже, если симки в слоте нет (этим занимается 01_rule)
	self:follow("network_registration"):debug(overview)	-- Пропускаем все узлы ниже, если регистрация есть
	self:follow("timeout"):debug()			-- Сколько ждать регистрации
	self:follow("switch"):debug(overview)			-- Переключаем слот, если вышел таймаут

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