local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения Сим-карты при отсутствии PING сети",
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
				local last_switch_time = nodes.slotinfo.last_switch_time and nodes.slotinfo.last_switch_time or 0
				if ((os.time() - last_switch_time) < 15) then return true end
			end
		},
	},

	-- Нет смысла проверять Ping, если сеть не установилась
	-- поэтому сюда добавлен узел для [break] - т.е. прерывания дальнейшей обработки правила
	-- если симка ещё не зарегистрирована.
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
		},
		{
		 	["break"] = function (nodes)
		 		return nodes.iface_up ~= true
		 	end
		}
    },

	host = {
		note = [[ Пробный хост для тестирования (обычно Google-сервер) ]],
		{
			["load-ubus"] = function (nodes)
				return {
					object = "uci",
					method = "get",
					params = {
						config = "tsmodem",
						section = "default",
						option = "ping_host"
					},
				}
			end
		}
	}, -- host

	ping_status = {
		note = [[ Результат PING-а сети ]],
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmping",
					method = "check",
					params = {},
				}
			end
		},
		{
			-- Проверяем дребезг: пропускаем обработку, если прошло мало времени с последнего изменения
			["skip"] = function (nodes)
				local debounce_time = 10
                local changed = nodes.ping_status.changed or 0
                local updated = nodes.ping_status.updated or 0
				local diff = math.abs(changed - updated)

				return (diff < debounce_time)
			end
		},
		{
			["websocket"] = function(nodes)
				return({
					sim_id = tostring(nodes.slotinfo.slot),
					ping_status = tostring(nodes.ping_status.value),
					timeout = nodes.timeout and nodes.timeout.inited or "60",
					wait_timer = nodes.timeout and tostring(nodes.timeout.value) or "60",
				})
			end
		},
		-- {
		-- 	["journal"] = function (nodes)
		-- 		local current_val = tostring(nodes.ping_status.value) or "0"
		-- 		local prev_val = tostring(nodes.ping_before) or "0"

        --         if current_val == prev_val then
        --             return nil
        --         end

        --         local event_name, command, response
        --         local sim_num = tonumber(nodes.slotinfo.slot) + 1

		-- 		if current_val == "0" then
		-- 			event_name = "Потеря связи (Ping Lost) SIM_" .. sim_num
		-- 			command = "Ping FAILED"
		-- 			response = "Host unreachable"
		-- 		else
		-- 			event_name = "Восстановление связи (Ping Restored) SIM_" .. sim_num
		-- 			command = "Ping OK"
		-- 			response = "Host reachable"
		-- 		end

        --         nodes.ping_status.prev_value = current_val

		-- 		return({
		-- 			name = event_name,
		-- 			datetime = os.date("%Y-%m-%d %H:%M:%S"),
		-- 			source = "GSM-модем [4_rule]",
		-- 			command = command,
		-- 			response = response
		-- 		})
		-- 	end
		-- },
		{
			["break"] = function(nodes)
				return (nodes.ping_status.value == "1")
			end
		},

	},

	-- Сохраняем состояние пинга для опционального логирования 
	-- ping_before = {
	-- 	note = [[ Сохраняем значение прошлого пинга ]],
	-- 	{
	-- 		["save"] = function (nodes)
	-- 			return(nodes.ping_status)
	-- 		end
	-- 	},
	-- },

	timeout = {
		note = [[ Таймаут отсутствия пинга.  ]],
		{
			["load-ubus"] = function(nodes)
				return {
					object = "uci",
					method = "get",
					params = {
						config = "tsmodem",
						section = "sim_" .. tostring(nodes.slotinfo.slot),
						option = "timeout_ping"
					},
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
			["journal"] = function (nodes)
				local new_slotid = nil
				local current_slotid = nodes.slotinfo.slot
				if(current_slotid == "0") then new_slotid = "1" end
				if(current_slotid == "1") then new_slotid = "0" end
				return({
					name = string.format('Переключение на SLOT-%s из-за отсутствия Ping', tostring(tonumber(new_slotid)+1)),
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					source = "Modem (04-rule)",
					command = "ping " .. tostring(luci.model.uci.cursor():get("tsmodem", "sim_" .. current_slotid, "ping_host")) or "",
					response = ""
				})
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
			["frozen"] = function (nodes)
				return 30
			end
		}
	} -- switch
	-- Test
} -- rule_setting

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
-- Alternatively, you may run debug via shell like this "applogic 03_rule title sim_id" (use 5 variable names maximum)
function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	local overview = {
		-- Жёлтый: правило не прервалось на ping_status - идёт отсчёт timeout_ping.
		-- Так бывает, когда пинга нет (value ~= "1") или действует антидребезг [skip]
		-- (статус менялся меньше 10 сек назад - тогда [break] не выполняется).
		-- RESULT: "1" / "0"; "1 (debounce)" при антидребезге; "-" если статуса нет.
		["ping_status"] = { ["yellow"] = function(nodes)
				local ping = type(nodes.ping_status) == "table" and nodes.ping_status or {}
				local v = ping.value
				local diff = math.abs((tonumber(ping.changed) or 0) - (tonumber(ping.updated) or 0))
				local debounce = (diff < 10)
				local shown = (v == nil or v == "") and "-" or tostring(v)
				if v == "1" and debounce then shown = shown .. " (debounce)" end
				return (v ~= "1" or debounce), shown
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

	self:follow("title"):debug() -- Use debug(ONLY) to check the var only

	self:follow("slotinfo"):debug()
	self:follow("iface_up"):debug()
    self:follow("ping_status"):debug(overview)
	self:follow("timeout"):debug()
	self:follow("switch"):debug(overview)

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
