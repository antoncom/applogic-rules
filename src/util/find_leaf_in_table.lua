
--[[ Find end-point value in the deep of table ]]
--[[ @vector is an array like this { "first", "second", "third" } ]]
--[[ tbl = {
        first = {
            second = {
                third = "founded value"
            }
        }
    }
]]
function find_leaf_in_table(tbl, vector)
	local found = false
	local res

	if (not tbl) or type(tbl) ~= "table" then
		return found, res
	end

	local next = (#vector > 0) and tostring(vector[1])
	if next and tbl[next] then
		if type(tbl[next]) == "table" then -- go deeper
			table.remove(vector, 1)
			return find_leaf_in_table(tbl[next], vector)
		else -- found
			found = true
			res = tostring(tbl[next])
		end
	else -- leaf not found with given vector
		found = false
		res = nil
	end
	return found, res
end

return find_leaf_in_table
