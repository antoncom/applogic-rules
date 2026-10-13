local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"



-- Правило 14 входит в путь установки GSM-соединения:
--   02_rule (регистрация в сети) -> 14_rule (провайдер и APN) -> 03_rule (поднять интерфейс "modem").
-- 14_rule прописывает в network.modem APN/логин/пароль провайдера Сим-карты активного слота.
-- 03_rule в режиме AUTO не поднимает интерфейс, пока провайдер не определён (см. узел ifup_modem в 03_rule).

-- Сколько секунд после переключения слота (или загрузки роутера) в режиме AUTO ждать
-- автоопределения провайдера. Потом берутся настройки адаптера AUTO (00000).
-- Это же значение использует 03_rule - держите их одинаковыми.
local APN_WAIT = 60

-- Сколько секунд прошло после переключения слота или загрузки роутера (что было позже)
local function since_slot_change(last_switch_time)
	local f = io.open("/proc/uptime", "r")
	local uptime = f and tonumber(f:read("*n")) or 0
	if f then f:close() end
	return math.min(os.time() - (tonumber(last_switch_time) or 0), uptime)
end

-- Конфиги, от которых зависят APN/логин/пароль интерфейса "modem".
-- Время изменения файла узнаётся системным вызовом stat - без обращения к UBUS/UCI.
local fs = require "nixio.fs"
local APN_CONFIGS = {
	"/etc/config/tsmodem",
	"/etc/config/tsmodem_adapter_provider",
	"/etc/config/network",
}
local function configs_stamp()
	local stamp = ""
	for _, path in ipairs(APN_CONFIGS) do
		local st = fs.stat(path) or {}
		stamp = stamp .. tostring(st.mtime) .. ":" .. tostring(st.size) .. ";"
	end
	return stamp
end

local rule = {}
local rule_setting = {
	title = {
		input = "Автоопределение провайдера и настройка APN интерфейса modem",
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
		{	-- Первые 5 сек после переключения слота правило не работает (как 02_rule и 03_rule).
			-- Больше ждать нельзя: APN должен быть прописан до того, как 03_rule поднимет интерфейс.
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
		{
			["websocket"] = function(nodes)
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

	apn_inputs = {
		note = [[ "Отпечаток" всего, от чего зависит APN: слот, провайдер, изменение конфигов.
		          Пока он не меняется, узлы adapters, apn_target, apn_current не обращаются к UCI ]],
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
				local detected = (type(nodes.apn_inputs) == "table") and nodes.apn_inputs or {}
				return table.concat({
					tostring(nodes.slotinfo.slot),
					tostring(detected.value), tostring(detected.comment),
					-- в режиме AUTO по истечении APN_WAIT меняется выбор адаптера
					tostring(since_slot_change(nodes.slotinfo.last_switch_time) >= APN_WAIT),
					configs_stamp(),
					-- страховка: раз в минуту перепроверяем, даже если ничего не изменилось
					tostring(math.floor(os.time() / 60)),
				}, "|")
			end
		},
	},

	adapters = {
		note = [[ Список провайдеров: APN, логин, пароль (tsmodem_adapter_provider) ]],
		{	-- Ничего не изменилось - конфиг не читаем
			["skip"] = function (nodes)
				return nodes.apn_inputs == nodes.apn_inputs_before
			end
		},
		{
			["load-ubus"] = function (nodes)
				return {
					object = "uci",
					method = "get",
					params = {
						config = "tsmodem_adapter_provider",
					},
				}
			end
		},
		{	-- Оставляем только нужные поля: так узел короче в отладочном отчёте (applogic debug)
			["func"] = function (nodes)
				local list = {}
				local values = (type(nodes.adapters) == "table" and nodes.adapters.values) or {}
				for id, a in pairs(values) do
					if a[".type"] == "adapter" and id ~= "template" then
						list[id] = {
							code = a.code or "",
							name = a.name or "",
							apn = a.gate_address or "",
							username = a.apn_login or "",
							password = a.apn_password or "",
						}
					end
				end
				return list
			end
		},
	},

	apn_target = {
		note = [[ APN/логин/пароль, которые должны стоять на интерфейсе "modem" для Сим-карты в активном слоте ]],
		{
			["skip"] = function (nodes)
				return nodes.apn_inputs == nodes.apn_inputs_before
			end
		},
		{	-- Результат автоопределения провайдера (тот же запрос, что в узле provider_detected, берётся из кэша)
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
				local sim = (type(nodes.provider_setting) == "table" and nodes.provider_setting.values) or {}
				local adapters = (type(nodes.adapters) == "table") and nodes.adapters or {}
				local detected = (type(nodes.apn_target) == "table") and nodes.apn_target or {}
				local AUTO = "00000"
				local provider_id = ""

				if (sim.autodetect_provider == "1" or sim.provider == AUTO) then
					-- Сеть: AUTO. Ждём, пока модем определит провайдера (AT+COPS? / +NITZ)
					local name = detected.value or ""
					local code = detected.comment or ""
					if name == "" then
						-- Провайдер ещё не определён. Ждём не дольше APN_WAIT, потом - настройки адаптера AUTO
						if since_slot_change(nodes.slotinfo.last_switch_time) < APN_WAIT then return "" end
					end

					for id, a in pairs(name ~= "" and adapters or {}) do
						if id ~= AUTO and ((code ~= "" and a.code == code) or (code == "" and a.name == name)) then
							provider_id = id
							break
						end
					end
					-- Провайдера нет в списке - берём настройки адаптера AUTO
					if provider_id == "" then provider_id = AUTO end
				else
					-- Провайдер задан вручную (в т.ч. CUSTOM_1 / CUSTOM_2): автоопределение не нужно
					provider_id = sim.provider or ""
				end

				local a = adapters[provider_id]
				if not a then return "" end

				return {
					provider_id = provider_id,
					provider_name = (a.name ~= "" and a.name) or provider_id,
					apn = a.apn,
					username = a.username,
					password = a.password,
				}
			end
		},
	},

	apn_current = {
		note = [[ APN/логин/пароль, которые сейчас стоят на интерфейсе "modem" ]],
		{
			["skip"] = function (nodes)
				return nodes.apn_inputs == nodes.apn_inputs_before
			end
		},
		{
			["load-ubus"] = function (nodes)
				return {
					object = "uci",
					method = "get",
					params = {
						config = "network",
						section = "modem",
					},
					cached = "no",
				}
			end
		},
		{	-- Оставляем только APN/логин/пароль
			["func"] = function (nodes)
				local v = (type(nodes.apn_current) == "table" and nodes.apn_current.values) or {}
				return {
					apn = v.apn or "",
					username = v.username or "",
					password = v.password or "",
				}
			end
		},
	},

	apn_apply = {
		note = [[ Прописать APN/логин/пароль в интерфейс "modem". netifd сам перезапустит интерфейс, если параметры изменились ]],
		{	-- Пропускаем, если ничего не изменилось, провайдер ещё не определён или настройки уже совпадают.
			-- После записи меняется время изменения /etc/config/network, поэтому на следующей итерации
			-- узлы перечитают network.modem и убедятся, что запись применилась.
			["skip"] = function (nodes)
				local t = nodes.apn_target
				if type(t) ~= "table" then return true end

				local c = (type(nodes.apn_current) == "table") and nodes.apn_current or {}
				return (c.apn == t.apn) and (c.username == t.username) and (c.password == t.password)
			end
		},
		{
			["load-ubus"] = function (nodes)
				local t = nodes.apn_target
				return {
					object = "uci",
					method = "set",
					params = {
						config = "network",
						section = "modem",
						values = {
							apn = t.apn,
							username = t.username,
							password = t.password,
						},
					},
					cached = "no",
				}
			end
		},
		{
			["load-ubus"] = function (nodes)
				return {
					object = "uci",
					method = "commit",
					params = { config = "network" },
					cached = "no",
				}
			end
		},
		{
			["load-ubus"] = function (nodes)
				return {
					object = "network",
					method = "reload",
					params = {},
					cached = "no",
				}
			end
		},
		{
			["journal"] = function (nodes)
				local t = nodes.apn_target
				return({
					name = "Настройки APN для SIM-" .. (tonumber(nodes.slotinfo.slot)+1) .. " (" .. tostring(t.provider_name) .. ")",
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					source = "Applogic  [14_rule]",
					command = "uci set network.modem; ubus call network reload",
					response = "APN: " .. t.apn .. (t.username ~= "" and (", login: " .. t.username) or "")
				})
			end
		},
	},

	apn_inputs_before = {
		note = [[ "Отпечаток" на предыдущей итерации ]],
		{
			["save"] = function (nodes)
				return nodes.apn_inputs
			end
		},
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
			["websocket"] = function(nodes)
				return({
					sim_id = tostring(nodes.slotinfo.slot),
					provider_name = nodes.provider_detected.value,
					provider_code = nodes.provider_detected.comment,
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
		note = [[ Идентификатор провайдера на предыдущей итерации ]],
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
	self:follow("slotinfo"):debug()			-- Пропускаем все узлы ниже первые 5 сек после переключения слотов
	self:follow("sim_found"):debug()		-- Пропускаем все узлы ниже, если симки в слоте нет
	self:follow("provider_setting"):debug()	-- Получаем текущие настройки провайдера из конфига
	self:follow("apn_inputs"):debug()		-- Изменилось ли что-то, от чего зависит APN (без обращения к UCI)
	self:follow("adapters"):debug()			-- Список провайдеров с их APN/логином/паролем
	self:follow("apn_target"):debug()		-- Какие APN/логин/пароль нужны для Сим-карты в слоте (с учётом AUTO)
	self:follow("apn_current"):debug()		-- Какие APN/логин/пароль сейчас на интерфейсе "modem"
	self:follow("apn_apply"):debug()		-- Если отличаются - прописываем и перезагружаем конфиг сети
	self:follow("apn_inputs_before"):debug()-- Запоминаем "отпечаток" для следующей итерации
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
