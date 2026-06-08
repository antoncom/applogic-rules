local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"


local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения Сим-карты при отсутствии PING сети",
	},

	-- Хммм, изучить построение зависимости правил - данное не имеет смысла без первых двух
	-- TO DO: Добавить проверку подключения к сети или перенастроить таймера так, что б предыдущие срабатывали раньше (ну или нет, если нам всё равно какое правило переключит сим-карту)
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
	}, -- sim_found

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
				if ((os.time() - last_switch_time) < 20) then return true end
			end
		}
	}, -- slotinfo

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
				-- print('===== ===== start ===== =====')
				-- print( luci.util.dumptable(nodes.ping_status) )
				-- print('===== =====  end  ===== =====')

				-- print('===== ===== start ===== =====')
				-- print(  luci.util.dumptable(nodes.slotinfo)  )
				-- print('===== =====  end  ===== =====')

				local debounce_time = 9
                -- Защита от nil
                local changed = nodes.ping_status.changed or 0
                local updated = nodes.ping_status.updated or 0
				local diff = math.abs(changed - updated)

                -- Возвращаем true (skip), если время меньше порога (защита активна)
				return (diff < debounce_time)
			end
		},
		{
			["websocket"] = function(nodes)
				return({
					sim_id = tostring(nodes.slotinfo.slot),
					timeout = nodes.timeout and nodes.timeout.inited or "120", 
					wait_timer = nodes.timeout and tostring(nodes.timeout.value) or "120",
					ping_status = tostring(nodes.ping_status.value)
				})
			end
		},
		{
			["journal"] = function (nodes)
				local current_val = tostring(nodes.ping_status.value or "0")
				local prev_val = tostring(nodes.ping_before or "0")

                if current_val == prev_val then
                    return nil
                end

                local event_name, command, response
                local sim_num = tonumber(nodes.slotinfo.slot) + 1

				if current_val == "0" then
					event_name = "Потеря связи (Ping Lost) SIM_" .. sim_num
					command = "Ping FAILED"
					response = "Host unreachable"
				else
					event_name = "Восстановление связи (Ping Restored) SIM_" .. sim_num
					command = "Ping OK"
					response = "Host reachable"
				end

                nodes.ping_status.prev_value = current_val

				return({
					name = event_name,
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					source = "GSM-модем [4_rule]",
					command = command,
					response = response
				})
			end
		},
		{
			["break"] = function(nodes)
				-- print('===== ===== start ===== =====')
				-- print( luci.util.dumptable(nodes) )
				-- print( nodes.ping_status.value )
				-- print('===== =====  end  ===== =====')

				return (nodes.ping_status.value == "1")
				-- return false -- for test
			end
		},
	}, -- ping_status	
	-- Сохраняем состояние пинга для опционального логирования 
	ping_before = {
		note = [[ Сохраняем значение прошлого пинга ]],
		{
			["save"] = function (nodes)
				return(nodes.ping_status)
			end
		},
	},-- ping_before	

	timeout = {
		note = [[ Таймаут отсутствия пинга.  ]],
		["default"] = 15,
		{
			["load-ubus"] = function(nodes)
				return {
					object = "uci",
					method = "get",
					params = {
						config = "tsmodem",
						section = "sim_" .. tostring(nodes.slotinfo.slot),	--  welllll -> string sim_(slotinfo.slot)
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
		{
			["websocket"] = function (nodes)
				-- nodes.ping_status.value

				-- print('===== ===== start ===== =====')
				-- print(  luci.util.dumptable(nodes.slotinfo)  )
				-- print('===== =====  end  ===== =====')

				-- print('>')
				-- print(luci.util.dumptable(nodes.timeout) )

				return({
					sim_id = tostring(nodes.slotinfo.slot),
					ping_status = tostring(nodes.ping_status.value),
					-- ping_status = "",
					timeout = tostring(nodes.timeout.inited),
					wait_timer = tostring(nodes.timeout.value),
				})
			end
		},
	},-- timeout

	switch = {
		note = [[ Переключить слот Сим-карт  ]],
		{
			["skip"] = function (nodes)
				local stil_wait = (nodes.timeout.value > 0)
				return stil_wait
			end
		},
		{
			["load-ubus"] = function (nodes)
				local new_slotid = nil
				local current_slotid = nodes.slotinfo.slot
				if(current_slotid == 0) then new_slotid = "1" else new_slotid = "0" end

				return {
					object = "tsmslot",
					method = "switch",
					params = { simid = new_slotid },
					cached = "no",
				}
			end
		},
		{
			["journal"] = function (nodes)
				return({
					name = '"Изменилось состояние PING",',
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					source = "Modem (04-rule)",
					command = "ping 8.8.8.8",				-- fix this
					response = "started"
				})
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


	-- These variables are included into debug overview (run "applogic debug" to get all rules overview)
	-- Green, Yellow and Red are measure of importance for Application logic
	-- Green is for timers and some passive variables,
	-- Yellow is for that nodes which switches logic - affects to normal application behavior
	-- Red is for some extraordinal application ehavior, like watchdog, etc.
	local overview = {	-- эт что?
		["lastping_timer"] = { ["yellow"] = [[ return (tonumber($lastping_timer) and tonumber($lastping_timer) > 0) ]] },
		["do_switch"] = { ["yellow"] = [[ return ($do_switch == "true") ]] },
	}

	-- Пропускаем выполнние правила, если tsmodem automation == "stop"
	if rule.parent.state.mode == "stop" then return end

	local all_rules = rule.parent.setting.rules_list.target

	-- Подумать про это:
--[[

	-- Пропускаем выполнения правила, если СИМ-карты нет в слоте
	local r01_wait_timer = tonumber(all_rules["01_rule"].setting.wait_timer.output)
	if (r01_wait_timer and r01_wait_timer > 0) then 
		if rule.debug_mode.enabled then print("------ 04_rule SKIPPED as r01_wait_timer > 0 -----") end
		return
	end

	-- Пропускаем выполнения правила, если СИМ не зарегистрирована в сети
	local r02_lastreg_timer = tonumber(all_rules["02_rule"].setting.lastreg_timer.output)
	if (r02_lastreg_timer and r02_lastreg_timer > 0) then 
		if rule.debug_mode.enabled then print("------ 04_rule SKIPPED as r02_lastreg_timer > 0 -----") end
		return
	end

	-- Пропускаем выполнения правила, если отрицательный баланс на счету Sim-карты
	local r03_sim_balance = tonumber(all_rules["03_rule"].setting.sim_balance.output)
	if (r03_sim_balance and r03_sim_balance <= 0) then
		--if rule.debug_mode.enabled then print("------ 04_rule SKIPPED as r03_sim_balance < 0 -----") end
		return
	end

]]--

	self:follow("title"):debug() -- Use debug(ONLY) to check the var only

	self:follow("sim_found"):debug()
	self:follow("slotinfo"):debug()

	self:follow("host"):debug()

    self:follow("ping_status"):debug()
    self:follow("ping_before"):debug()

	self:follow("timeout"):debug(overview)

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
