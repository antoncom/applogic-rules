-- Вспомогательная функция - проверяет существует ли на шине UBUS указаный объект и метод

-- Положительный результат проверки запоминаем на CHECK_TTL секунд.
-- Без этого каждый оператор [load-ubus] (около 40 на итерацию, даже при попадании в кэш)
-- делал два запроса к ubusd - conn:objects() (список ВСЕХ объектов шины) и conn:signatures(),
-- что давало основную часть нагрузки applogic на CPU.
-- Отрицательный результат не запоминаем: объект, появившийся позже (например, после
-- перезапуска сервиса), будет найден на следующем же вызове. Если объект исчезнет с шины
-- в течение CHECK_TTL, сам ubus-вызов вернёт nil - это обрабатывается в [load-ubus] как и раньше.
local CHECK_TTL = 30
local known = {}

function check_ubus_object(conn, obj, method)
	if conn then
		local key = tostring(obj) .. "\0" .. tostring(method)
		local now = os.time()
		if known[key] and now < known[key] then
			return true, nil
		end

		local namespaces = conn:objects()
		local obj_exist = false
		local method_exist = false
		local err = nil
		for i, n in ipairs(namespaces) do
			if obj == n then
				obj_exist = true
				local signatures = conn:signatures(n)
				if signatures and type(signatures) == "table" then
					for p, s in pairs(signatures) do
						if (method == p or method == nil) then
							method_exist = true
							break
						end
					end
				end
				break
			end
		end
		if not obj_exist then
			err = string.format("Object [%s] doesn't exist on ubus.", obj)
		elseif not method_exist then
			err = string.format("Method [%s] doesn't exist on ubus object [%s].", method, obj)
		end

		if obj_exist and method_exist then
			known[key] = now + CHECK_TTL
		else
			known[key] = nil
		end
		return (obj_exist and method_exist), err
	end
	return false, "applogic.util.checkubus: No UBUS connection found."
end

return check_ubus_object
