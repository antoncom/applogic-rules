local util = require "luci.util"
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
	    ["nodename"] = {
			note = "",
	        source = { code, value, noerror },
	        input = { value, noerror },
	        output = { value, noerror },
	        operator = {
	            { op_name, code, value, noerror }, -- for operators: load-ubus, load-rule, subscribe
                { op_name, body, value, noerror }, -- for other operators
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


function report:print_var(nodename, level, iter)
	local vars = report.debug.variables
	local rule_has_error = (report.debug.noerror == false)

	if not vars[nodename] then
		print(string.format("applogic: report:print() can't find var [%s]", nodename))
		vars[nodename].noerror = true
		return
	end

	local var_has_error = report.debug.variables[nodename].noerror == false
	if not vars[nodename].input then vars[nodename].input = "empty" end
	if not vars[nodename].output then vars[nodename].output = "empty" end


	if (rule_has_error and var_has_error and level == "ERROR") or level == "INFO" then
		-- Just create a report with some content
		local ftable = ft.new()
		local check = ""
		local operator_rows = {}
		local current_row

		ftable:set_cell_prop(ft.ANY_ROW, 1, ft.CPROP_TEXT_ALIGN, ft.ALIGNED_LEFT)
		ftable:set_cell_prop(ft.ANY_ROW, 2, ft.CPROP_TEXT_ALIGN, ft.ALIGNED_LEFT)
		ftable:set_cell_prop(1, ft.ANY_COLUMN, ft.CPROP_ROW_TYPE, ft.ROW_HEADER)

		current_row = 1
		ftable:write_ln(string.format("[ %s ][ %s ] variable attributes value", report.rule.ruleid, nodename):upper(), "", "", "RESULTS ON THE ITERATION", "#"..tostring(report.rule.iteration))
		ftable:add_separator()

		current_row = 2
		check = (not vars[nodename].input["noerror"]) and "✖" or "✔"
		ftable:write_ln("default", "", "", vars[nodename].input["value"], check)
		if vars[nodename].input["noerror"] then
			ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
		else
			ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_RED)
		end

		if vars[nodename]["operator"] then
			for _, operator in ipairs(vars[nodename]["operator"]) do
				current_row = current_row + 1
				table.insert(operator_rows, current_row)
				check = (not operator["noerror"]) and "✖" or "✔"

				if operator["op_name"] == "load-ubus" or operator["op_name"] == "load-rule" or operator["op_name"] == "subscribe" then
					ftable:write_ln("operator", "[".. operator["op_name"] .. "]", operator["code"], operator["value"], check)
				else
					ftable:write_ln("operator", "[".. operator["op_name"] .. "]", string.format("%s", operator["body"]), operator["value"], check)
				end

				if operator["noerror"] then
					ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
				else
					ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_RED)
				end
			end
		end

		current_row = current_row + 1
		check = (not vars[nodename].output["noerror"]) and "✖" or "✔"
		ftable:write_ln("output", "", "", vars[nodename].output["value"], check)
		if vars[nodename].output["noerror"] then
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
	local rule_has_error = (report.debug.noerror == false)

	report.iteration = report.iteration + 1

	if (rule_has_error and level == "ERROR") or level == "INFO" then

		--local iteration = rule.iteration
		local ftable = ft.new()
		local check = ""
		local current_row

		ftable:set_cell_prop(ft.ANY_ROW, 1, ft.CPROP_TEXT_ALIGN, ft.ALIGNED_LEFT)
		ftable:set_cell_prop(1, ft.ANY_COLUMN, ft.CPROP_ROW_TYPE, ft.ROW_HEADER)

		current_row = 1
		local rule_title = (vars.title and vars.title.input) and vars.title.input.value or ""

		rule_title = string.format("[%s] %s", report.rule.ruleid, rule_title)
		ftable:write_ln(rule_title, "", "", "", "")
		ftable:add_separator()

		current_row = 2
		ftable:write_ln("VARIABLE", "NOTES", "PASS LOGIC", "RESULTS ON THE ITERATION", "#"..tostring(report.iteration))
		ftable:add_separator()

		for nodename, vardata in  util.spairs(vars,
			function(a,b)
				return (vars[a].order < vars[b].order)
			end) do

			if nodename ~= "title" then
				current_row = current_row + 1

				-- Make passlogic cell
				local passlogic = ""
				if vars[nodename]["operator"] then
					for _, operator in ipairs(vars[nodename]["operator"]) do
						if "skip" == operator["op_name"] then
							if operator["value"] then
								passlogic = "[skip]"
								ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
								break
							else
								passlogic = ""
								ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)
							end
						elseif "ui-update" == operator["op_name"] then
							passlogic = string.format("%s[ui-update]", passlogic)
							ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)
						elseif "frozen" == operator["op_name"] then
							if operator["value"] and tonumber(operator["value"]) then
								passlogic = string.format("%s[frozen] %03d", passlogic, tonumber(operator["value"]) or operator["value"])
								--passlogic = string.format("%s[frozen]", passlogic)
							end
						end
					end
				end

				check = (not vars[nodename].noerror) and "✖" or "✔"
				ftable:write_ln(nodename, vardata["note"], passlogic, vardata.output.value, check)
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

function report:overview(rules, iteration)
	local ftable = ft.new()
	local check = ""
	local current_row

	ftable:set_cell_prop(ft.ANY_ROW, 1, ft.CPROP_TEXT_ALIGN, ft.ALIGNED_LEFT)
	ftable:set_cell_prop(1, ft.ANY_COLUMN, ft.CPROP_ROW_TYPE, ft.ROW_HEADER)

	current_row = 1
	ftable:write_ln("RULEID", "VARIABLE", "NOTES", "PASS LOGIC", "RESULT", "#"..tostring(iteration))
	ftable:add_separator()

	for ruleid, rule in  util.spairs(rules) do
		if rule["default"].overviewed_vars then
			local vars = rule.debug.variables
			local nodename = ""
			local vardata

			for i = 1, #rule["default"].overviewed_vars do
				nodename = rule["default"].overviewed_vars[i]
				vardata = vars[nodename]

				-- print("nodename",nodename)
				-- log("vardata",vardata)

				current_row = current_row + 1

				-- Make colorizing overview level (green, yellow, red)
				if(vardata.overview and vardata.overview["yellow"] and vardata.overview["yellow"] == true) then
					ftable:set_cell_prop(current_row, 1, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_YELLOW)
					ftable:set_cell_prop(current_row, 2, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_YELLOW)
					ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_YELLOW)
					ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_YELLOW)
				elseif(vardata.overview and vardata.overview["red"] and vardata.overview["red"] == true) then
					ftable:set_cell_prop(current_row, 1, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_RED)
					ftable:set_cell_prop(current_row, 2, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_RED)
					ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_RED)
					ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_RED)
				elseif(vardata.overview and vardata.overview["green"] and vardata.overview["green"] == true) then
					ftable:set_cell_prop(current_row, 2, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)
					ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)
				else
					ftable:set_cell_prop(current_row, 1, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)
					ftable:set_cell_prop(current_row, 2, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)
					ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)
					ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)
				end

				-- Make passlogic cell
				local passlogic = ""
				if vars[nodename]["operator"] then
					for _, operator in ipairs(vars[nodename]["operator"]) do
						if "skip" == operator["op_name"] then
							if operator["value"] then
								passlogic = "[skip]"
								ftable:set_cell_prop(current_row, 4, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
								break
							else
								passlogic = ""
								ftable:set_cell_prop(current_row, 4, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)
							end
						elseif "frozen" == operator["op_name"] then
							if operator["value"] and tonumber(operator["value"]) then
								passlogic = string.format("%s[frozen] %03d", passlogic, tonumber(operator["value"]) or operator["value"])
								--passlogic = string.format("%s[frozen]", passlogic)
							end
						end
					end
				end

				check = (not vars[nodename].noerror) and "✖" or "✔"
				ftable:write_ln(rule.ruleid, nodename, vardata["note"], passlogic, vardata.output.value, check)
				if vardata["noerror"] then
					ftable:set_cell_prop(current_row, 6, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
				else
					ftable:set_cell_prop(current_row, 6, ft.CPROP_CONT_FG_COLOR, ft.COLOR_RED)
				end

			end
		else
			-- current_row = current_row + 1
			-- ftable:write_ln(ruleid, "-", "Nothing to overview..", "-", "-", "")
		end
	end

	-- CELL SPANS
	--ftable:set_cell_span(1, 1, 5) -- rule title row



	-- CELLS STYLE
	ftable:set_cell_prop(1, ft.ANY_COLUMN, ft.CPROP_CONT_TEXT_STYLE, ft.TSTYLE_BOLD)
	ftable:set_cell_prop(ft.ANY_ROW, 1, ft.CPROP_CONT_TEXT_STYLE, ft.TSTYLE_BOLD)
	ftable:set_cell_prop(1, 4, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)

	-- Setup border style
	ftable:set_border_style(ft[style])
	-- Print ftable
	print(tostring(ftable))

end


function report:queu(rules, iteration)
	local ftable = ft.new()
	local check = ""
	local current_row
	local queu = rules.subscription.queu
	local varlist = rules.subscription.vars

	function getEvname(evmatch)
		return evmatch.evname
	end

	function getMatch(evmatch)
		local varlinks = evmatch.subscribed_vars
		if (#varlinks > 0 and #varlinks[1] > 0 and varlinks[1][1]["subscribe"] and varlinks[1][1]["subscribe"].match) then
			return util.serialize_json(varlinks[1][1]["subscribe"].match)
		else
			return ""
		end
	end

	function getTotalEvents(evmatch)
		local events = evmatch.events
		--print("--- REPORT -- evmatch: ", evmatch.evname)
		--util.dumptable(util.keys(evmatch))

		return #events
	end

	function getVarnames(evmatch)
		-- local varnotes = ""
		-- for _,var in ipairs(evmatch.subscribed_vars) do
		-- 	varnotes = varnotes .. var.note .. ", "
		-- end
		-- return varnotes
		return table.concat(evmatch.subscribed_varnames, " ")
	end

	ftable:set_cell_prop(ft.ANY_ROW, 1, ft.CPROP_TEXT_ALIGN, ft.ALIGNED_LEFT)
	ftable:set_cell_prop(1, ft.ANY_COLUMN, ft.CPROP_ROW_TYPE, ft.ROW_HEADER)

	current_row = 1
	ftable:write_ln("Подписка переменных на события UBUS", "#"..tostring(iteration))
	ftable:add_separator()

	current_row = 2
	ftable:write_ln("UBUS OBJ", "EVENT NAME", "FILTER", "VARS", "EVNUM")
	ftable:add_separator()

	for ubusobj, evmatches in util.kspairs(queu) do
		for evmatch_key, evmatch in util.kspairs(evmatches) do
			local evtotal = getTotalEvents(evmatch)
			local evname = evmatch.evname
			local varnames = getVarnames(evmatch)
			local evmatch_humanread = getMatch(evmatch)
			ftable:write_ln(ubusobj, evname, evmatch_humanread, varnames, evtotal)
		end
	end

	-- CELL SPANS
	ftable:set_cell_span(1, 1, 5) -- title row


		-- CELLS STYLE
	ftable:set_cell_prop(1, ft.ANY_COLUMN, ft.CPROP_CONT_TEXT_STYLE, ft.TSTYLE_BOLD)
	ftable:set_cell_prop(2, ft.ANY_COLUMN, ft.CPROP_CONT_TEXT_STYLE, ft.TSTYLE_BOLD)
	ftable:set_cell_prop(ft.ANY_ROW, 1, ft.CPROP_CONT_TEXT_STYLE, ft.TSTYLE_BOLD)
	--ftable:set_cell_prop(1, 4, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)

	-- Setup border style
	ftable:set_border_style(ft[style])
	-- Print ftable
	print(tostring(ftable))

end


function report:clear()
	-- clear error statuses, but keep debug data untouched, as they are linked to real rule ongoing data

	-- local vars = report.debug.variables
	-- report.debug.noerror = true
	-- for varname, debugdata in pairs(vars) do
	-- 	debugdata.noerror = true
	-- end

	report.debug = nil
	report.rule = nil

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
