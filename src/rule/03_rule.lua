local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"



local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения Сим-карты, если баланс ниже минимума",
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
		{	-- Если нет симки в слоте, то пропускаем дальнейшую обработку правила
			["break"] = function (nodes)
				return (nodes.sim_found.value ~= "true")
			end
		}
	},

	uci_slot_config = {
		note = [[ Настройки активного слота SIM-карты ]],
		{
			["load-ubus"] = function (nodes)
				return {
					object = "uci",
					method = "get",
					params = {
						config = "tsmodem",
						section = "sim_" .. tostring(nodes.slotinfo.slot),
						option = nil
					},
				}
			end
		},
	},

	provider_detected = {
		note = [[ Идентификатор провайдера после автоопределения или указанный вручную в tsmodem конфиге ]],
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
			["func"] = function (nodes)
				local autodetect_provider = nodes.uci_slot_config.values.autodetect_provider
				if autodetect_provider == "1" then
					-- Провайдер определен автоматически
					return {
						value = nodes.provider_detected.value,		-- имя оператора
						comment = nodes.provider_detected.comment,	-- id оператора
					}
				elseif autodetect_provider == "0" then
					-- Провайдер указан вручную в tsmodem конфиге
					return {
						value = "",
						comment = nodes.uci_slot_config.values.provider, -- id оператора
					}
				end
			end
		},
		{
			["break"] = function (nodes)
				local autodetect_provider = nodes.uci_slot_config.values.autodetect_provider
				local provider_id = nodes.provider_detected.comment
				-- print('provider_id: ' .. provider_id)

				if autodetect_provider == "1" then
					local provider_name = nodes.provider_detected.value
					return not (tonumber(provider_id) and provider_id ~= "0" and provider_name ~= "")
				elseif autodetect_provider == "0" then
					return not (tonumber(provider_id) and provider_id ~= "0")
				end
			end
		},
	},

	uci_provider_config = {
        note = [[ Настройки провайдера для GSM-оператора активной симки ]],
		{
			["load-ubus"] = function (nodes)
				local provider_id = nodes.provider_detected.comment
				return {
					object = "uci",
					method = "get",
					params = {
						config = "tsmodem_adapter_provider",
						section = provider_id,
						option = nil
					},
				}
			end
		},
    },

	check_balance_on_sim_registered = {
	    note = [[ Отправляем SMS-запрос о балансе кактолько симка зарегистрировалась ]],
		{
			["skip"] = function (nodes)
				-- Если CREG установился в 1 и с этого момента прошло более 10 сек
				return ((tonumber(nodes.sim_found.updated) - tonumber(nodes.sim_found.changed)) > 10)
			end
		},
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmodem.sms",
		        	method = "send_sms",
		        	params = {
		        		phone = nodes.uci_provider_config.values.balance_sms_phone, 
		        		text = nodes.uci_provider_config.values.balance_sms_text
		        	},
		        }
	    	end
		},
		{
			-- Запросив баланс сразу после регистации Симки, замораживаем, чтобы не было повторов ubus-запроса в эти 10 сек.
			["frozen"] = function (nodes)
				return 10
			end
		},
	},

	check_balance_daily = {
	    note = [[ Отправляем SMS-запрос о балансе раз в день ]],
	    {
			["timeout"] = function(nodes)
				return 86400	-- число секунд в 24-х часах
			end
		},

		{
			["skip"] = function (nodes)
				return (nodes.check_balance_daily.value > 0)
			end
		},
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmodem.sms",
		        	method = "send_sms",
		        	params = {
		        		phone = nodes.uci_provider_config.values.balance_sms_phone, 
		        		text = nodes.uci_provider_config.values.balance_sms_text
		        	},
		        }
	    	end
		},
		{
			["frozen"] = function (nodes)
				return 5
			end
		},
	},

	check_balance_after_switch = {
	    note = [[ Запрашиваем баланс после переключения Sim-слота ]],
		{
			["skip"] = function (nodes)
				local last_switch_time = nodes.slotinfo.last_switch_time or 0
				if last_switch_time == 0 then return true end

				local saved_switch_time = tonumber(nodes.check_balance_after_switch) or 0
				return (saved_switch_time == last_switch_time)
			end
		},
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmodem.sms",
		        	method = "send_sms",
		        	params = {
		        		phone = nodes.uci_provider_config.values.balance_sms_phone,
		        		text = nodes.uci_provider_config.values.balance_sms_text
		        	},
		        }
	    	end
		},
		{
			["save"] = function (nodes)
				return nodes.slotinfo.last_switch_time
			end
		},
		{
			["frozen"] = function (nodes)
				return 5
			end
		},
	},

	actual_balance = {
	    note = [[ Текущий статус баланса (число, * (значит в процессе), либо "" - если последний запрос был неудачен) ]],
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmodem.driver",
		        	method = "balance",
		        	params = {},
		        }
	    	end
		},
	},

	is_balance_ok = {
		note = [[ Проверка соответствия баланса минимальному лимиту ]],
		{
			["func"] = function (nodes)
				local BALANCE_ACTUAL = tonumber(nodes.actual_balance.value)
				if BALANCE_ACTUAL == nil then return false end
				local BALANCE_MIN = tonumber(nodes.uci_slot_config.values.balance_min) or 0
				return (BALANCE_ACTUAL >= BALANCE_MIN)
			end
		},
	},

	retry_balance = {
	    note = [[ Повторный SMS-запрос баланса, если значение баланса отсутствует в tsmodem ]],
		{
			["timeout"] = function(nodes)
				return 20
			end
		},
		{
			["skip"] = function (nodes)
				if nodes.actual_balance.value ~= "" then return true end
				return (nodes.retry_balance.value > 0)
			end
		},
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmodem.sms",
		        	method = "send_sms",
		        	params = {
		        		phone = nodes.uci_provider_config.values.balance_sms_phone,
		        		text = nodes.uci_provider_config.values.balance_sms_text
		        	},
		        }
	    	end
		},
		{
			["frozen"] = function (nodes)
				return 5
			end
		},
	},

	actual_balance_ui_update = {
		note = [[ Отправляет баланс в веб-интерфейс ]],

		{
			["websocket"] = function (nodes)
				return({
					sim_id = tostring(nodes.slotinfo.slot),
					sim_balance = nodes.actual_balance,
					is_balance_ok = tostring(nodes.is_balance_ok),
				})
			end
		},
		{
			["break"] = function (nodes)
				local bal_undefined = (tonumber(nodes.actual_balance.value) == nil)
				return nodes.is_balance_ok or bal_undefined
			end
		},
	},

	timeout = {
		note = [[ Таймер ожидания при низком балансе  ]],
		{   -- Запускаем таймер
			["timeout"] = function(nodes)
				return tonumber(nodes.uci_slot_config.values.timeout_bal)
			end
		},
		{
			["websocket"] = function(nodes)
				return({
					sim_id = tostring(nodes.slotinfo.slot),
					sim_balance = nodes.actual_balance,
					is_balance_ok = tostring(nodes.is_balance_ok),

					timeout = nodes.timeout and nodes.timeout.inited or "60",
					wait_timer = nodes.timeout and tostring(nodes.timeout.value) or "60",
				})
			end
		},
	},
	switch = {
		note = [[ Переключить слот Сим-карт  ]],
		{
			["break"] = function (nodes)
				if nodes.timeout.value > 0 then
					return true
				else
					return false
				end
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
					params = { slotid = nodes.switch },
					cached = "no",
				}
			end
		},
		{
			["journal"] = function (nodes)
				return({
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = 'Переключение Sim-слота (баланс ниже минимума)',
					source = "STM32 (03_rule)",
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
	self:follow("slotinfo"):debug()			-- Пропускаем все узлы ниже, если прошло не более 20 сек после начала переключения слотов
	self:follow("sim_found"):debug()		-- Пропускаем все узлы ниже, если симка найдена в слоте
	self:follow("uci_slot_config"):debug() -- Получаем настройки активного слота Сим-карты
	self:follow("provider_detected"):debug() -- Определяем какой провайдер определился на Сим-карте
	self:follow("uci_provider_config"):debug() -- Получаем кортокий тел.номер оператора для получения баланса через СМС
	self:follow("check_balance_on_sim_registered"):debug() -- Посылаем SMS-команду получения баланса как только симка зарегистрировалась
	self:follow("check_balance_daily"):debug() -- Посылаем SMS-команду получения баланса 1 раз в день
	self:follow("check_balance_after_switch"):debug() -- Посылаем SMS-команду получения баланса после переключения слота
	self:follow("actual_balance"):debug()		-- Текущее значение баланса
	self:follow("is_balance_ok"):debug()		-- Проверка соответствия баланса минимальному лимиту
	self:follow("retry_balance"):debug()		-- Повторный запрос баланса через смс, если баланс не был получен
	self:follow("actual_balance_ui_update"):debug()	-- Отправляем значение баланса в веб-интерфейс
	self:follow("timeout"):debug() -- Таймаут ожидания при низком балансе
	self:follow("switch"):debug() -- Переключаем слот, после окончания таймаута
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
