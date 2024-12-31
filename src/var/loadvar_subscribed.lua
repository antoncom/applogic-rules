
local util = require "luci.util"
local log = require "applogic.util.log"
local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua
local checkubus = require "applogic.util.checkubus"
local cjson = require "cjson"


local loadvar_subscribed = {}

-- Очередь поступивших событий на загрузку переменной по subscribe.
-- Это нужно в том случае, когда события следуют одно за другим с маленьким интервалом,
-- а при этом, загруженная переменная должна хранить значение, полученное от текущей подписки
-- в течении 2-х итераций всех правил с тем, чтобы, вне зависимости от того в какой момент переменная была загружена по subscribe,
-- её значение успели воспринять все другие перменные правила при обработке своих значений.

loadvar_subscribed.queue = {
	-- ["network.interface"] = {
	--		[0] = {
	--			["name"] = name,
	--			["msg"] = msg,
	--			["subscribers"] = { varlink1, varlink2, etc},	-- ссылки на переменные правил, которые нужно будет загрузить данными по подписке
	--			["iteration"] = nil								-- на какой итерации данные загрузятся в varlink.input
	--		}
	-- }
}	

-- Когда мы извлекаем очередное значение из очереди пришедхих по подписке
-- мы храним его здесь 2 итерации правил
loadvar_subscribed_current_value = nil
-- Пример:
-- {
	--	["name"] = name,
	--	["msg"] = msg,
	--	["subscribers"] = { varlink1, varlink2, etc},			-- ссылки на переменные правил, которые нужно будет загрузить данными по подписке
	--	["iteration"] = nil										-- на какой итерации данные загрузились в varlink.input
-- }

-- Данная колбэк функция выполняется в ответ на поступившее событие на шине UBUS
-- Функция помещает данные о событии в очередь loadvar_subscribed.queue
function loadvar_subscribed:cb_subscribe() 
	return function(ubus_objname, evmsg, evname, rule, match_msg, match_name)
		if ((evname == match_name or match_name == "") and loadvar_subscribed:matched_evmsg(evmsg, match_msg)) then
			local ev = {
				["name"] = evname,
				["msg"] = evmsg,
				["subscribers"] = {},		-- {varlink1, varlink2, etc}
				["iteration"] = rule.iteration	-- номер итерации на которой событие добвлено в очередь
			}
			table.insert(rule.parent.subscription[ubus_objname], util.clone(ev, true))
			print("++++ INSERTED TO SUBSCRIPTION: " .. ubus_objname .. " " .. evmsg.interface)
		end
	end
end

function loadvar_subscribed:matched_evmsg(ev, pattern)
	local msg_matched = false
	local evmsg = ev
	if not evmsg then return end

	for attr,value in util.kspairs(pattern) do
		if (evmsg[attr] and evmsg[attr] == value) then
			msg_matched = true
			break
		end
	end
	return msg_matched

end

function loadvar_subscribed:load(varname, rule)
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

	local varlink = rule.setting[varname]
	local subscription = rule.parent.subscription

	local result = {}
	local noerror = true
	local err = ""

	--[[ LOAD FROM UBUS ON SUBSCRIBTION ]]
	local ubus_objname = string.format("%s", (varlink.source.ubus or ""))
	local match_name = string.format("%s", (varlink.source.event_name or ""))
	local match_msg = varlink.source.match or {}

	noerror, err = checkubus(rule.conn, ubus_objname)
	if noerror then


		-- Если на данный UBUS-объект ещё не было подписки
		-- то создаём таблицу для очереди будущих событий, поступающих от данного ubus-объекта
		if (not subscription[ubus_objname]) then
			subscription[ubus_objname] = {}

			-- и подписываемся на шину ubus
			rule:subscribe_ubus(varlink.source.ubus, loadvar_subscribed:cb_subscribe(), rule, match_msg, match_name)
		end


		-- Если подписка на данный ubus-объект уже есть,
		-- Смотрим нет ли уже в очереди событий в данного объекта
		if (#subscription[ubus_objname] > 0) then
			-- Если есть, то загружаем в нашу переменную данные, поступившие по подписке,
			-- но только в том случае, если данные соответствуюи имени события и отбору по содержимому сообщения
			local ev = subscription[ubus_objname][1]
			if ((ev.name == match_name or match_name == "") and loadvar_subscribed:matched_evmsg(ev.msg, match_msg)) then
				varlink.subtotal = util.serialize_json(ev.msg)
			else
				-- пропускаем загрузку по подписке, т.к. событие не удовлетворяет matched-условиям
			end
		end
	end


	if rule.debug_mode.enabled then
		if (noerror) then
			debug(varname, rule):source_subscribe(ubus_objname, match_name, varlink.subtotal, noerror, varlink.source)
		else
			debug(varname, rule):source_subscribe(ubus_objname, match_name, err, noerror, varlink.source)
		end
	end

	--return (rule.subscriptions[subscribe_opertor_id] and util.serialize_json(rule.subscriptions[subscribe_opertor_id])) or ""
end

return loadvar_subscribed
