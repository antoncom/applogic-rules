local util = require "luci.util"

function store_db(varname, mdf_name, modifier, rule)
	local debug
	if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

	local output_file = "/etc/output.txt" -- Accessible file location
	local max_entries = 20 -- Set the limit here
	local varlink = rule.setting[varname] or {}
	local param_list = modifier.param_list or {}
	local result = {}
	local noerror = true

	-- Function to read existing entries from the file
	local function read_existing_entries()
		local entries = {}
		local file = io.open(output_file, "r")
		if file then
			for line in file:lines() do
				table.insert(entries, line) -- Add each line to the entries table
			end
			file:close()
		end
		return entries
	end

	-- Function to write all entries back to the file
	local function write_entries(entries)
		local file, err = io.open(output_file, "w") -- Open the file in write mode to overwrite it
		if file then
			for _, entry in ipairs(entries) do
				file:write(entry .. "\n") -- Write each entry followed by a newline
			end
			file:close()
		else
			noerror = false
			if rule.debug_mode.enabled then
				result = "Error opening file: " .. err
				debug(varname, rule):modifier(mdf_name, pretty(param_list):gsub("\t", "  "), result, noerror)
			end
		end
	end

	-- Function to manage the max entries limit
	local function enforce_limit(entries)
		if #entries >= max_entries then
			table.remove(entries, 1) -- Remove the oldest entry (first entry in the table)
		end
	end

	if #param_list > 0 then
		local params, name = {}, ''
		for i = 1, #param_list do
			name = param_list[i]
			if name == varname then
				if util.contains({ "journal_reg", "journal_usb", "journal_stm" }, name) then
					name = "journal"
				end
				params[name] = varlink.subtotal or ""
			else
				params[name] = rule.setting[name] and rule.setting[name].output or ""
			end
		end
		params["ruleid"] = rule.ruleid

		-- Serialize data to JSON
		local ui_data = util.serialize_json(params)

		-- Read existing entries from the file
		local entries = read_existing_entries()

		-- Enforce the max entries limit
		enforce_limit(entries)

		-- Append the new entry
		table.insert(entries, ui_data)

		-- Write all entries back to the file
		write_entries(entries)

		--[[if rule.debug_mode.enabled then
			debug(varname, rule):modifier(mdf_name, pretty(param_list):gsub("\t", "  "), ui_data, noerror)
		end ]]
	end
end

return store_db
