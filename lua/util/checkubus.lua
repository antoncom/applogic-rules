function check_ubus_object(conn, obj, method)
	local namespaces = conn:objects()
	local obj_exist = false
	local method_exist = false
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
	return (obj_exist and method_exist)
end

return check_ubus_object
