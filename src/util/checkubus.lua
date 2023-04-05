function check_ubus_object(conn, obj, method)
	if conn then
		local namespaces = conn:objects()
		local obj_exist = false
		local method_exist = false
		local err_text = ""
		for i, n in ipairs(namespaces) do
			if obj == n then
				obj_exist = true
				local signatures = conn:signatures(n)
				for p, s in pairs(signatures) do
					if method == p then
						method_exist = true
						break
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
		return (obj_exist and method_exist), err
	end
	return false, "applogic.util.checkubus: No UBUS connection found."
end

return check_ubus_object
