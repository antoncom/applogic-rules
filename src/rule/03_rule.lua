local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"

-- Правило 03 замыкает путь установки GSM-соединения:
--   02_rule (регистрация в сети) -> 14_rule (провайдер и APN) -> 03_rule (поднять интерфейс "modem").
-- APN/логин/пароль в network.modem прописывает 14_rule. В режиме AUTO (Сеть: AUTO)
-- 03_rule не поднимает интерфейс, пока провайдер не определён, чтобы соединение
-- сразу устанавливалось с APN этого провайдера.

-- Сколько секунд после переключения слота (или загрузки роутера) в режиме AUTO ждать
-- автоопределения провайдера. Должно совпадать с APN_WAIT в 14_rule.
local APN_WAIT = 60

-- Сколько секунд прошло после переключения слота или загрузки роутера (что было позже)
local function since_slot_change(last_switch_time)
	local f = io.open("/proc/uptime", "r")
	local uptime = f and tonumber(f:read("*n")) or 0
	if f then f:close() end
	return math.min(os.time() - (tonumber(last_switch_time) or 0), uptime)
end

local rule = {}
local rule_setting = {
	title = {
		input = "Правило переключения Cим-карты при отсутствии сетевого GSM-соединения",
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
		{	-- Первые 5 сек после переключения слота правило не работает (как в 01_rule и 02_rule).
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
		{	-- Без карты соединения быть не может: пустым слотом занимается 01_rule.
			-- Нужно ещё и потому, что после извлечения карты значение reg остаётся "1"
			-- до тех пор, пока модем сам не сообщит +CREG: 0 (около 10 сек).
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
		{	-- Нет регистрации: этим случаем занимается 02_rule
			["break"] = function(nodes)
				local sim_registered = (nodes.network_registration.value == "1") or (nodes.network_registration.value == "5")
				return not sim_registered
			end
		},
	},


	iface_up = {
		note = [[ Поднялся ли интерфейс "modem" - Link до интернет-провайдера ]],

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
			["websocket"] = function(nodes)
				return({
					sim_id = tostring(nodes.slotinfo.slot),
					netlink = tostring(nodes.iface_up),
					timeout = nodes.timeout and nodes.timeout.inited or "60",
					wait_timer = nodes.timeout and tostring(nodes.timeout.value) or "60",
				})
			end
		},
		{
			["break"] = function(nodes)
				return (nodes.iface_up == true)
			end
		},

    },

	sim_setting = {
		note = [[ Настройки Сим-карты активного слота: провайдер задан вручную или AUTO ]],
		{
			["load-ubus"] = function (nodes)
				return {
					object = "uci",
					method = "get",
					params = {
						config = "tsmodem",
						section = "sim_" .. tostring(nodes.slotinfo.slot),
					},
				}
			end
		},
	},

	provider_name = {
		note = [[ Провайдер, определённый модемом (пусто - ещё не определён) ]],
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
				return (type(nodes.provider_name) == "table" and nodes.provider_name.value) or ""
			end
		},
	},

	ifup_modem = {
		note = [[ Установить сетевое соединение на интерфейсе "modem" ]],
		{
			["break"] = function(nodes)
				return (nodes.iface_up == true)
			end
		},
		{	-- Режим AUTO: не поднимаем интерфейс, пока не определён провайдер.
			-- APN этого провайдера прописывает 14_rule. Оно выполняется после 03_rule на том же такте,
			-- поэтому ждём, чтобы провайдер был известен и на предыдущей итерации (provider_name_before).
			-- Таймер timeout_link (узел timeout) при этом идёт, так что переключение слота по таймауту работает.
			["skip"] = function(nodes)
				local s = (type(nodes.sim_setting) == "table" and nodes.sim_setting.values) or {}
				local AUTO = (s.autodetect_provider == "1" or s.provider == "00000")
				if not AUTO then return false end

				if nodes.provider_name ~= "" and nodes.provider_name == nodes.provider_name_before then
					return false
				end

				-- Провайдера может не оказаться в списке: ждём не дольше APN_WAIT,
				-- потом 14_rule пропишет настройки адаптера AUTO, и интерфейс поднимется с ними.
				return since_slot_change(nodes.slotinfo.last_switch_time) < APN_WAIT
			end
		},
		{
			["load-ubus"] = function(nodes)
				return {
					object = "network.interface.modem",
					method = "up",
					params = {},
				}
			end
		},
		{
		 	["func"] = function (nodes)
		 		return nodes.ifup_modem
		 	end
		},
		{
		 	["frozen"] = function (nodes)
		 		return 30
		 	end
		},
    },

	provider_name_before = {
		note = [[ Провайдер на предыдущей итерации (для узла ifup_modem) ]],
		{
			["save"] = function (nodes)
				return nodes.provider_name
			end
		},
	},


	timeout = {
		note = [[ Таймаут отсутствия сетевого соединения  ]],
		{	-- Загружаем значение таймера из конфига
			["load-ubus"] = function (nodes)
				return {
					object = "uci",
					method = "get",
					params = {
						config = "tsmodem",
						section = "sim_" .. tostring(nodes.slotinfo.slot),
						option = "timeout_link",
					}
				}
			end
		},
		{   -- Запускаем таймер
			["timeout"] = function(nodes)
				return tonumber(nodes.timeout.value)
			end
		},
		{
			["websocket"] = function(nodes)
				return({
					sim_id = tostring(nodes.slotinfo.slot),
					timeout = nodes.timeout and nodes.timeout.inited or "60",
					wait_timer = nodes.timeout and tostring(nodes.timeout.value) or "60",
					netlink = tostring(nodes.iface_up)
				})
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
					name = 'Переключение Sim-слота (нет сетевого соединения)',
					source = "Network (03_rule)",
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
		-- Жёлтый: интерфейс "modem" не поднят - правило пытается его поднять и идёт отсчёт timeout_link.
		-- Условие обратное [break] узла iface_up.
		-- RESULT: "up" / "down"; "-" если статуса интерфейса нет.
		["iface_up"] = { ["yellow"] = function(nodes)
				local up = nodes.iface_up
				if up == true then return false, "up" end
				return true, ((up == false) and "down" or "-")
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
	self:follow("slotinfo"):debug()				-- Пропускаем все узлы ниже первые 5 сек после переключения слотов
	self:follow("sim_found"):debug()			-- Пропускаем все узлы ниже, если симки в слоте нет (01_rule)
	self:follow("network_registration"):debug()	-- Пропускаем все узлы ниже, если нет регистрации (02_rule)
	self:follow("iface_up"):debug(overview)				-- Пропускаем все узлы ниже, если соединение есть
	self:follow("sim_setting"):debug()			-- Провайдер задан вручную или AUTO
	self:follow("provider_name"):debug()		-- Какой провайдер определил модем
	self:follow("ifup_modem"):debug()			-- Пробуем поднять интерфейс, не чаще раза в 30 сек (AUTO - после определения провайдера)
	self:follow("provider_name_before"):debug()	-- Запоминаем провайдера для следующей итерации
	self:follow("timeout"):debug()				-- Сколько ждать соединения
	self:follow("switch"):debug(overview)				-- Переключаем слот, если вышел таймаут

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