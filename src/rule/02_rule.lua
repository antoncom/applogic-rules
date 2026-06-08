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
		{	-- Если идёт процесс переключения, то пропускаем дальнейшую обработку правила
			["break"] = function (nodes)
				local last_switch_time = nodes.slotinfo.last_switch_time or 0
				if ((os.time() - last_switch_time) < 30) then return true end
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
				return (nodes.sim_found.value ~= "true")
			end
		}
	},

	iface_up = {
		note = [[ Поднялся ли интерфейс TSMODEM - Link до интернет-провайдера ]],
		{
			["load-ubus"] = function(nodes)
				return {
					object = "network.interface.modem",
					method = "status",
					params = {},
				}
			end
		},
		{
		 	["func"] = function (nodes)
		 		return nodes.iface_up.up
		 	end
		}
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
				if (nodes.iface_up) then return nodes.network_registration.value end
				if not (nodes.iface_up) then return "8" end
			end
		},
		{
			["websocket"] = function(nodes)
				return({
					sim_id = tostring(nodes.slotinfo.slot),
					timeout = nodes.timeout and nodes.timeout.inited or "600",
					wait_timer = nodes.timeout and tostring(nodes.timeout.value) or "600",
					network_registration = tostring(nodes.network_registration)
				})
			end
		},
		{
			["break"] = function(nodes)
				return (nodes.network_registration == "1")
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
				local stil_wait = (nodes.timeout.value > 0)
				return stil_wait
			end
		},
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

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end

	local all_rules = rule.parent.setting.rules_list.target

	self:follow("title"):debug()
	self:follow("slotinfo"):debug()			-- Пропускаем все узлы ниже, если прошло не более 20 сек после начала переключения слотов
	self:follow("sim_found"):debug()		-- Пропускаем все узлы ниже, если симка найдена в слоте
	self:follow("iface_up"):debug()
	self:follow("network_registration"):debug()
	self:follow("timeout"):debug()			-- Сколько ждать регистрации
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
