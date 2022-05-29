
local util = require "luci.util"
local log = require "applogic.util.log"

local ft = require "applogic.util.fort"
ft.ANY_ROW = 4294967295
ft.ANY_COLUMN = 4294967295
local style = "BOLD2_STYLE"

local report = {
	iteration = 0,
	noerror = true,
}
--[[ Example
    ["varname"] = {
        source = { code, value, noerror },
        input = { value, noerror },,
        output = { value, noerror },,
        modifiers = {
            ["1_func"] = { body, value, noerror }
        }
    },
    iteration = 0,
	noerror = false,
	show() prints the report
]]

function report:print(varname, level, iteration)
	if not report[varname] then
		print(string.format("applogic: report:print() can't find var [%s]", varname))
		report.noerror = true
		return
	else
		if not report[varname].input then report[varname].input = "empty" end
		if not report[varname].output then report[varname].output = "empty" end
	end

	if (not report.noerror and level == "ERROR") or level == "INFO"  then

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
		ftable:write_ln(string.format("[ %s ] variable attributes value",varname):upper(), "", "", "RESULTS ON THE ITERATION", "#"..tostring(iteration))
		ftable:add_separator()

		current_row = 2
		check = (not report[varname].input["noerror"]) and "✖" or "✔"
		ftable:write_ln("input", "", "", report[varname].input["value"], check)
		if report[varname].input["noerror"] then
			ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
		else
			ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_RED)
		end

		if report[varname]["source"] then
			current_row = 3
			check = (not report[varname].source["noerror"]) and "✖" or "✔"
			ftable:write_ln("source", report[varname].source["type"], report[varname].source["code"], report[varname].source["value"], check)
			if report[varname].source["noerror"] then
				ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
			else
				ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_RED)
			end

		end
		if report[varname]["modifier"] then
			for name, mdf in util.kspairs(report[varname]["modifier"]) do
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
		check = (not report[varname].output["noerror"]) and "✖" or "✔"
		ftable:write_ln("output", "", "", report[varname].output["value"], check)
		if report[varname].output["noerror"] then
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
	report.noerror = true
end

return report
