
local util = require "luci.util"
local log = require "applogic.util.log"
local md5 = require "md5" -- https://github.com/keplerproject/md5/blob/master/tests/test.lua
local checkubus = require "applogic.util.checkubus"

local loadvar_subscribed = {}

-- Очередь поступивших событий на загрузку переменной по subscribe.
-- Это нужно в том случае, когда события следуют одно за другим с маленьким интервалом,
-- а при этом, загруженная переменная должна хранить значение, полученное от текущей подписки
-- в течении 2-х итераций всех правил с тем, чтобы, вне зависимости от того в какой момент переменная была загружена по subscribe,
-- её значение успели воспринять все другие перменные правила при обработке своих значений.

loadvar_subscribed.queue = {
	-- [0] = {
	--		event_name = name,
	--		payload = msg,
	-- }

	-- При этом msg содержит таблицу вида:
	-- msg = {
	--    answer = "AT+CMGS: 405 OK"      -- OK, ERROR
	-- }
}	

-- Когда мы извлекаем очередное значение из очереди пришедхих по подписке
-- мы храним его здесь 2 итерации правил
loadvar_subscribed_current_value = nil
-- Пример:
-- {
--		event_name = name,
--		payload = msg,
--		rules_iteration = nil		-- указывает на которой итерации правил переменая была загружена данным значением
-- }

-- Данная колбэк функция выполняется в ответ на поступившее событие на шине UBUS
function loadvar_subscribed:cb_subscribe(varlink)
	return function(msg, name)
		if(varlink.source.event_name == name) then
			local data = {
				event_name = name,
				payload = msg,
			}
			table.insert(loadvar_subscribed.queue, util.clone(data, true))

			print("+++ New value on subscription for [" .. name .. "] event!")
			util.dumptable(data)
		end
	end
end

function loadvar_subscribed:load(varname, rule)
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

	local setting = rule.setting
	local varlink = rule.setting[varname]

	local subscribe_opertor_id = ""
	local result = {}
	local noerror = true
	local err = ""

	--[[ LOAD FROM UBUS ON SUBSCRIBTION ]]
	local object = string.format("%s", (varlink.source.ubus or ""))
	local event_name = string.format("%s", (varlink.source.event_name or ""))

	noerror, err = checkubus(rule.conn, object)
	if noerror then

		-- If UBUS has an [object] where some event with [event_name] is fired
		-- then only one subscribing method is run all over all rules.
		-- It avoids duplicating of subscription method for the same UBUS object/event
		subscribe_opertor_id = "subscribed_"..rule.ruleid.."_"..varname.."_"..object.."_"..event_name
		
		if (not rule.subscriptions[subscribe_opertor_id]) then
			--print("I'm going to make subscription like this: " .. subscribe_opertor_id)
			local variable = rule:subscribe_ubus(varlink.source.ubus, loadvar_subscribed:cb_subscribe(varlink))
			rule.subscriptions[subscribe_opertor_id] = "Just made subscriptions for " .. subscribe_opertor_id
		else
			--print("[tsmsms] No subscribe_ubus() done for [" .. subscribe_opertor_id .. "], as it has been already operated before.")
		end

		-- Значение загруженное в переменную по подписке должно хранится не более 2-х итераций всех правил.
		-- Если очередь поступивших по подписке значений содержит более 1 элемента,
		-- то спустя 2 цикла мы загружаем следующее значение из очереди в переменую заместо старого значения (поступившего ранее)
		-- Если очередь пуста (то есть не поступило следующих значений по подписке),
		-- то очищаем переменную

		-- Берём первые данные из очереди поступивших значений
		-- Присваиваем номер итерации, на которой переменная была загружена
		-- А также функцию проверки is_lived_twice() показывающую что данное значение "живет" в переменной уже 2 итерации

		if(not (type(loadvar_subscribed_current_value) == "table")) then
			if(#loadvar_subscribed.queue > 0) then
				loadvar_subscribed_current_value = table.remove(loadvar_subscribed.queue, 1)
				loadvar_subscribed_current_value["rules_iteration"] = tostring(rule.iteration)
				loadvar_subscribed_current_value["is_lived_twice"] = function()
					return ((rule.iteration - tonumber(loadvar_subscribed_current_value["rules_iteration"])) == 2)
				end
				loadvar_subscribed_current_value["lives_on"] = function()
					return (rule.iteration - tonumber(loadvar_subscribed_current_value["rules_iteration"]))
				end
			end
		else
			-- На следующей итерации, если текущее значение присутствует
			-- то проверяем его на признак is_lived_twice()
			-- Если да - очищаем переменную
			-- if loadvar_subscribed_current_value.is_lived_twice() then
			-- 	loadvar_subscribed_current_value = nil
			-- end
			if (loadvar_subscribed_current_value.lives_on() == 1) then

				result = util.clone(loadvar_subscribed_current_value, true)
				noerror = result["payload"] and result["payload"]["answer"]
				if not noerror then 
					err = "[loadvar_subscribed.lua]: No payload found!"
				end
			
			elseif (loadvar_subscribed_current_value.lives_on() == 2) then
				result = nil
				loadvar_subscribed_current_value = nil
				noerror = true
			end
		end


		varlink.subtotal = result and util.serialize_json(result) or ""

	end


	if rule.debug_mode.enabled then
		if (noerror) then
			debug(varname, rule):source_subscribe(object, event_name, varlink.subtotal, noerror, varlink.source)
		else
			debug(varname, rule):source_subscribe(object, event_name, err, noerror, varlink.source)
		end
	end

	--return (rule.subscriptions[subscribe_opertor_id] and util.serialize_json(rule.subscriptions[subscribe_opertor_id])) or ""
end

return loadvar_subscribed
