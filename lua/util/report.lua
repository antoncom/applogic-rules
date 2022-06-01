
local util = require "luci.util"
local log = require "applogic.util.log"

local ft = require "applogic.util.fort"
ft.ANY_ROW = 4294967295
ft.ANY_COLUMN = 4294967295
local style = "BOLD2_STYLE"

local report = {
	iteration = 0
}
--[[ Print table of particular variable in a rule ]]

--[[ Example
	variables = {
	    ["varname"] = {
			note = "",
	        source = { code, value, noerror },
	        input = { value, noerror },
	        output = { value, noerror },
	        modifiers = {
	            ["1_func"] = { body, value, noerror }
	        },
			iteration = 0,
			noerror = false,
			order = 1,

	    },
	},
	noerror = false,
    iteration = 0,
	noerror = false,
]]


function report:print_var(varname, level, iter)
	local vars = report.debug.variables
	--log("VARS", vars)
	local rule_has_error = report.debug.noerror == false
	local var_has_error = report.debug.variables[varname].noerror == false

	if not vars[varname] then
		print(string.format("applogic: report:print() can't find var [%s]", varname))
		vars[varname].noerror = true
		return
	else
		if not vars[varname].input then vars[varname].input = "empty" end
		if not vars[varname].output then vars[varname].output = "empty" end
	end

	if (rule_has_error and var_has_error and level == "ERROR") or level == "INFO" then

		-- Just create a report with some content
		local ftable = ft.new()
		local check = ""
		local source_row
		local modifier_rows = {}
		local current_row

		ftable:set_cell_prop(ft.ANY_ROW, 1, ft.CPROP_TEXT_ALIGN, ft.ALIGNED_LEFT)
		ftable:set_cell_prop(ft.ANY_ROW, 2, ft.CPROP_TEXT_ALIGN, ft.ALIGNED_LEFT)
		ftable:set_cell_prop(1, ft.ANY_COLUMN, ft.CPROP_ROW_TYPE, ft.ROW_HEADER)

		current_row = 1
		ftable:write_ln(string.format("[ %s ] variable attributes value",varname):upper(), "", "", "RESULTS ON THE ITERATION", "#"..tostring(report.rule.iteration))
		ftable:add_separator()

		current_row = 2
		check = (not vars[varname].input["noerror"]) and "✖" or "✔"
		ftable:write_ln("input", "", "", vars[varname].input["value"], check)
		if vars[varname].input["noerror"] then
			ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
		else
			ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_RED)
		end

		if vars[varname]["source"] then
			current_row = 3
			check = (not vars[varname].source["noerror"]) and "✖" or "✔"
			ftable:write_ln("source", vars[varname].source["type"], vars[varname].source["code"], vars[varname].source["value"], check)
			if vars[varname].source["noerror"] then
				ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
			else
				ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_RED)
			end

		end
		if vars[varname]["modifier"] then
			for name, mdf in util.kspairs(vars[varname]["modifier"]) do
				current_row = current_row + 1
				table.insert(modifier_rows, current_row)
				check = (not mdf["noerror"]) and "✖" or "✔"
				ftable:write_ln("modifier", "[".. name .. "]", string.format("%s", mdf["body"]), mdf["value"], check)
				if mdf["noerror"] then
					ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
				else
					ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_RED)
				end
			end
		end

		current_row = current_row + 1
		check = (not vars[varname].output["noerror"]) and "✖" or "✔"
		ftable:write_ln("output", "", "", vars[varname].output["value"], check)
		if vars[varname].output["noerror"] then
			ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
		else
			ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_RED)
		end

		-- CELL SPANS
		ftable:set_cell_span(1, 1, 3) -- header row
		ftable:set_cell_span(2, 1, 3) -- input value row

		-- CELL SPAN FOR OUTPUT ROW
		ftable:set_cell_span(current_row, 1, 3)

		-- HEADER STYLE
		ftable:set_cell_prop(1, ft.ANY_COLUMN, ft.CPROP_CONT_TEXT_STYLE, ft.TSTYLE_BOLD)
		ftable:set_cell_prop(ft.ANY_ROW, 1, ft.CPROP_CONT_TEXT_STYLE, ft.TSTYLE_BOLD)
		ftable:set_cell_prop(1, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)

		-- Setup border style
		ftable:set_border_style(ft[style])
		-- Print ftable
		print(tostring(ftable))

	end
end


--[[ Print table of all vars of the rule ]]

function report:print_rule(level, iteration)
	local vars = report.debug.variables
	local rule_has_error = report.debug.noerror == false

	report.iteration = report.iteration + 1

	if (rule_has_error and level == "ERROR") or level == "INFO" then

		--local iteration = rule.iteration
		local ftable = ft.new()
		local check = ""
		local current_row

		ftable:set_cell_prop(ft.ANY_ROW, 1, ft.CPROP_TEXT_ALIGN, ft.ALIGNED_LEFT)
		ftable:set_cell_prop(1, ft.ANY_COLUMN, ft.CPROP_ROW_TYPE, ft.ROW_HEADER)

		current_row = 1
		local rule_title = (vars.title and vars.title.output) and vars.title.output.value or ""
		rule_title = string.format("[%s] %s", report.rule.ruleid, rule_title)
		ftable:write_ln(rule_title, "", "", "", "")
		ftable:add_separator()

		current_row = 2
		ftable:write_ln("VARIABLE", "NOTES", "PASS LOGIC", "RESULTS ON THE ITERATION", "#"..tostring(report.iteration))
		ftable:add_separator()

		--for varname, vardata in  util.kspairs(report.variables) do
		for varname, vardata in  util.spairs(vars,
			function(a,b)
				return (vars[a].order < vars[b].order)
			end) do

		--log("VARS", vardata)
			if varname ~= "title" then

				current_row = current_row + 1

				-- Make passlogic cell
				local passlogic = ""
				if vars[varname]["modifier"] then
					for name, mdf in util.kspairs(vars[varname]["modifier"]) do
						if "skip" == name:sub(3) then
							if mdf["value"] then
								passlogic = "[skip]"
								ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
							else
								passlogic = ""
								ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)
							end
						elseif "trigger" == name:sub(3) then
							if mdf["value"] then
								passlogic = "[trigger]"
								ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
							else
								passlogic = ""
								ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
							end
						elseif "frozen" == name:sub(3) then
							if mdf["value"] and mdf["value"]:len() > 0 then
								passlogic = string.format("%s[frozen] %03d", passlogic, tonumber(mdf["value"]) or mdf["value"])
								--passlogic = string.format("%s[frozen]", passlogic)
							end
						end
					end
				end

				check = (not vars[varname].noerror) and "✖" or "✔"
				ftable:write_ln(varname, vardata["note"], passlogic, vardata.output.value, check)
				if vardata["noerror"] then
					ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
				else
					ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_RED)
				end
			end
		end

		-- CELL SPANS
		ftable:set_cell_span(1, 1, 5) -- rule title row


		-- CELLS STYLE
		ftable:set_cell_prop(1, ft.ANY_COLUMN, ft.CPROP_CONT_TEXT_STYLE, ft.TSTYLE_BOLD)
		ftable:set_cell_prop(2, ft.ANY_COLUMN, ft.CPROP_CONT_TEXT_STYLE, ft.TSTYLE_BOLD)
		ftable:set_cell_prop(ft.ANY_ROW, 1, ft.CPROP_CONT_TEXT_STYLE, ft.TSTYLE_BOLD)
		ftable:set_cell_prop(1, 4, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)

		-- Setup border style
		ftable:set_border_style(ft[style])
		-- Print ftable
		print(tostring(ftable))

	end
end

function report:clear()
	-- clear error statuses, but keep debug data untouched, as they are linked to real rule ongoing data
	local vars = report.debug.variables
	report.debug.noerror = true
	for varname, debugdata in pairs(vars) do
		debugdata.noerror = true
	end
	--report.iteration = 0
end

local metatable = {
	__call = function(table, rule)
        if not report.debug then
            report.debug = rule.debug	-- Link to the populated debug data
			report.rule = rule
        end
		return table
	end
}
setmetatable(report, metatable)

return report
