local debug_mode = require "applogic.debug_mode"
local rule_init = require "applogic.util.rule_init"

-- Имя UCI-конфигурации с доверенными телефонами и разрешёнными командами.
-- Присланный файл называется "tsmsmscomm"; если на приборе он лежит под другим именем, поправьте здесь.
local UCI_CONFIG = "tsmsmscomm"

local MAX_ANSWER_LEN = 300		-- ограничение длины ответного SMS, байт
local MAX_SEND_TRIES = 6		-- сколько раз пробуем отправить ответ, если tsmsms занят
local SEND_RETRY_SEC = 5		-- пауза между попытками отправки, сек.

-- Очередь ответных SMS. Живёт между итерациями, т.к. файл правила загружается один раз.
-- Элемент: { phone = "...", text = "...", tries = 0 }
local outbox = {}
local last_sms_key = nil		-- для отсева повторно пришедшего события


-- Оставляем от номера только цифры и сравниваем последние 10:
-- так "+79371191365", "79371191365" и "89371191365" считаются одним номером.
local function phone_key(phone)
	local digits = tostring(phone or ""):gsub("%D", "")
	if #digits < 10 then return nil end
	return digits:sub(-10)
end

local function is_trusted(phone)
	local key = phone_key(phone)
	if not key then return false end

	local trusted = false
	local uci = require "luci.model.uci".cursor()		-- новый курсор, чтобы видеть свежую конфигурацию
	uci:foreach(UCI_CONFIG, "remote_control", function(s)
		if phone_key(s.trusted_phone) == key then trusted = true end
	end)
	return trusted
end

-- Возвращает shell-команду из конфигурации, соответствующую тексту SMS, либо "".
-- Сам текст SMS никогда не выполняется: он только выбирает строку из белого списка.
local function find_shell_command(sms_text)
	local wanted = tostring(sms_text or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
	if wanted == "" then return "" end

	local found = ""
	local uci = require "luci.model.uci".cursor()
	uci:foreach(UCI_CONFIG, "sms_command", function(s)
		if found == "" and s.sms_command and s.shell_command
		   and tostring(s.sms_command):lower() == wanted then
			found = tostring(s.shell_command)
		end
	end)
	return found
end

-- Обрезаем длинный ответ, не разрывая символ UTF-8 посередине
local function cut(text, limit)
	if #text <= limit then return text end
	text = text:sub(1, limit)
	text = text:gsub("[\128-\191]*$", "")
	text = text:gsub("[\192-\255]$", "")
	return text .. "..."
end


local rule = {}
local rule_setting = {
	title = {
		input = "Управление роутером по SMS",
	},

	incoming = {
		note = [[ Новое SMS, полученное по подписке от сервиса Tsmsms ]],
		{
			["subscribe"] = {
				ubus = "tsmsms",
				evname = "NEW-SMS-RECEIVED",
				match = {},
			}
		},
	},

	trusted = {
		note = [[ Отправитель есть в списке trusted_phone? "true" / "false" ]],
		{
			["skip"] = function (nodes)
				return (type(nodes.incoming) ~= "table")
			end
		},
		{
			["func"] = function (nodes)
				return is_trusted(nodes.incoming.sender) and "true" or "false"
			end
		},
		{
			["func"] = function (nodes)
				local sms = nodes.incoming
				local key = tostring(sms.sender) .. "|" .. tostring(sms.date) .. "|" .. tostring(sms.message)
				if key == last_sms_key then return "duplicate" end	-- это же SMS уже обработано на прошлой итерации
				last_sms_key = key									-- запоминаем для сравнения со следующим событием
				return is_trusted(sms.sender) and "true" or "false"
			end
		},
	},

	command = {
		note = [[ Shell-команда из конфигурации, соответствующая тексту SMS ]],
		{
			["skip"] = function (nodes)
				return (nodes.trusted ~= "true")
			end
		},
		{
			["func"] = function (nodes)
				return find_shell_command(nodes.incoming.message)
			end
		},
	},

	answer = {
		note = [[ Выполнить команду и поставить её вывод в очередь на отправку ]],
		{
			["skip"] = function (nodes)
				return (nodes.command == "" or nodes.command == nil)
			end
		},
		{	-- Оператор [bash] выполняет команду только если в узле уже есть значение
			["func"] = function (nodes)
				return "run"
			end
		},
		{
			["bash"] = [[ sh -c $command 2>&1 ]]
		},
		{
			["func"] = function (nodes)
				local out = tostring(nodes.answer or "")
				if out == "" then out = "OK (no output)" end
				out = cut(out, MAX_ANSWER_LEN)

				table.insert(outbox, {
					phone = tostring(nodes.incoming.sender),
					text = out,
					tries = 0,
				})
				return out
			end
		},
		{
			["journal"] = function (nodes)
				return({
					datetime = os.date("%Y-%m-%d %H:%M:%S"),
					name = 'Команда по SMS от ' .. tostring(nodes.incoming.sender),
					source = "Remote control (15_rule)",
					command = tostring(nodes.incoming.message):lower(),		-- текст SMS, например "ver"
					response = "[" .. tostring(nodes.command) .. "] → \n" .. tostring(nodes.answer)
				})
			end
		},
	},

	reply = {
		note = [[ Отправить ответ абоненту по SMS через Tsmsms. Повторяем, если сервис занят. ]],
		{
			["skip"] = function (nodes)
				return (#outbox == 0)
			end
		},
		{
			["load-ubus"] = function (nodes)
				return {
					object = "tsmsms",
					method = "send",
					params = {
						phone = outbox[1].phone,
						text = outbox[1].text,
					},
					cached = "no",
				}
			end
		},
		{
			["func"] = function (nodes)
				local item = outbox[1]
				local status = (type(nodes.reply) == "table") and tostring(nodes.reply.status) or "no reply"

				if status == "ok" or status == "started" then
					table.remove(outbox, 1)
					return "sent to " .. item.phone
				end

				item.tries = item.tries + 1
				if item.tries >= MAX_SEND_TRIES then
					table.remove(outbox, 1)
					return "dropped after " .. item.tries .. " tries, last status: " .. status
				end
				return "retry #" .. item.tries .. ", status: " .. status
			end
		},
		{
			["frozen"] = function (nodes)
				return SEND_RETRY_SEC
			end
		},
	},

}

-- Use "ERROR", "INFO" to override the debug level
-- Use /etc/config/applogic to change the debug level
-- Use :debug(ONLY) - to debug single variable in the rule
function rule:make()
	debug_mode.level = "ERROR"
	rule.debug_mode = debug_mode
	local ONLY = rule.debug_mode.level

	self:follow("title"):debug()
	self:follow("incoming"):debug()		-- Очередное SMS из очереди подписки (по одному за итерацию)
	self:follow("trusted"):debug()		-- Проверяем отправителя
	self:follow("command"):debug()		-- Ищем команду в белом списке
	self:follow("answer"):debug()		-- Выполняем и кладём ответ в очередь
	self:follow("reply"):debug()		-- Отправляем ответы из очереди

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