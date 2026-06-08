
-- Формирует вывод отладочной таблицы в режиме debug

local util = require "luci.util"
local ft = require "applogic.util.fort"
ft.ANY_ROW = 4294967295
ft.ANY_COLUMN = 4294967295
local style = "BOLD2_STYLE"

local report = {
	iteration = 0
}
--[[ Print table of particular node in a rule ]]

--[[ Example
	nodes = {
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


function report:print_node(nodename, level, iter)
	local nodes = report.debug.nodes
	local rule_has_error = (report.debug.noerror == false)

	if not nodes[nodename] then
		print(string.format("applogic: report:print() can't find node [%s]", nodename))
		nodes[nodename].noerror = true
		return
	end

	local node_has_error = report.debug.nodes[nodename].noerror == false
	if not nodes[nodename].input then nodes[nodename].input = "empty" end
	if not nodes[nodename].output then nodes[nodename].output = "empty" end


	if (rule_has_error and node_has_error and level == "ERROR") or level == "INFO" then
		-- Just create a report with some content
		local ftable = ft.new()
		local check = ""
		local operator_rows = {}
		local current_row

		ftable:set_cell_prop(ft.ANY_ROW, 1, ft.CPROP_TEXT_ALIGN, ft.ALIGNED_LEFT)
		ftable:set_cell_prop(ft.ANY_ROW, 2, ft.CPROP_TEXT_ALIGN, ft.ALIGNED_LEFT)
		ftable:set_cell_prop(1, ft.ANY_COLUMN, ft.CPROP_ROW_TYPE, ft.ROW_HEADER)

		current_row = 1
		ftable:write_ln(string.format("[ %s ][ %s ] node attributes value", report.rule.ruleid, nodename):upper(), "", "", "RESULTS ON THE ITERATION", "#"..tostring(report.rule.iteration))
		ftable:add_separator()

		current_row = 2
		check = (not nodes[nodename].input["noerror"]) and "✖" or "✔"
		ftable:write_ln("default", "", "", nodes[nodename].input["value"], check)
		if nodes[nodename].input["noerror"] then
			ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
		else
			ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_RED)
		end

		if nodes[nodename]["operator"] then
			for _, operator in ipairs(nodes[nodename]["operator"]) do
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
		check = (not nodes[nodename].output["noerror"]) and "✖" or "✔"
		ftable:write_ln("output", "", "", nodes[nodename].output["value"], check)
		if nodes[nodename].output["noerror"] then
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


--[[ Print table of all nodes of the rule ]]

function report:print_rule(level, iteration)
	local nodes = report.debug.nodes
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
		local rule_title = (nodes.title and nodes.title.input) and nodes.title.input.value or ""

		rule_title = string.format("[%s] %s", report.rule.ruleid, rule_title)
		ftable:write_ln(rule_title, "", "", "", "")
		ftable:add_separator()

		current_row = 2
		ftable:write_ln("VARIABLE", "NOTES", "PASS LOGIC", "RESULTS ON THE ITERATION", "#"..tostring(report.iteration))
		ftable:add_separator()

		local break_outer = false

		for nodename, nodedata in  util.spairs(nodes,
			function(a,b)
				return (nodes[a].order < nodes[b].order)
			end) do

			if nodename ~= "title" then
				current_row = current_row + 1

				-- Make passlogic cell
				local passlogic = ""
				if nodes[nodename]["operator"] then
					for _, operator in ipairs(nodes[nodename]["operator"]) do
						if "skip" == operator["op_name"] then
							if operator["value"] then
								passlogic = "[skip]"
								ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
								break
							else
								--passlogic = ""
								ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)
							end
						elseif "break" == operator["op_name"] then
							if operator["value"] then
								passlogic = passlogic.."\n[break]"
								ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
								break_outer = true;
								--break
							--else
							--	ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)
							end
						elseif "ui-update" == operator["op_name"] then
							passlogic = string.format("%s[ui-update]", passlogic)
							ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)
						elseif "timeout" == operator["op_name"] then
							passlogic = string.format("%s\n[timeout]", passlogic)
							ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_WHITE)
						elseif "frozen" == operator["op_name"] then
							if operator["value"] and tonumber(operator["value"]) then
								passlogic = string.format("%s\n[frozen] %03d", passlogic, tonumber(operator["value"]) or operator["value"])
								--passlogic = string.format("%s[frozen]", passlogic)
							end
						elseif "save" == operator["op_name"] then
							passlogic = "[save]"
							ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_YELLOW)
						end
					end
				end

				check = (not nodes[nodename].noerror) and "✖" or "✔"
				ftable:write_ln(nodename, nodedata["note"], passlogic, nodedata.output.value, check)
				if nodedata["noerror"] then
					ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_GREEN)
				else
					ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_RED)
				end
			end

			if break_outer then break end
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
		if rule["default"].overviewed_nodes then
			local nodes = rule.debug.nodes
			local nodename = ""
			local nodedata

			for i = 1, #rule["default"].overviewed_nodes do
				nodename = rule["default"].overviewed_nodes[i]
				nodedata = nodes[nodename]

				-- print("nodename",nodename)
				-- log("nodedata",nodedata)

				current_row = current_row + 1

				-- Make colorizing overview level (green, yellow, red)
				if(nodedata.overview and nodedata.overview["yellow"] and nodedata.overview["yellow"] == true) then
					ftable:set_cell_prop(current_row, 1, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_YELLOW)
					ftable:set_cell_prop(current_row, 2, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_YELLOW)
					ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_YELLOW)
					ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_YELLOW)
				elseif(nodedata.overview and nodedata.overview["red"] and nodedata.overview["red"] == true) then
					ftable:set_cell_prop(current_row, 1, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_RED)
					ftable:set_cell_prop(current_row, 2, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_RED)
					ftable:set_cell_prop(current_row, 3, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_RED)
					ftable:set_cell_prop(current_row, 5, ft.CPROP_CONT_FG_COLOR, ft.COLOR_LIGHT_RED)
				elseif(nodedata.overview and nodedata.overview["green"] and nodedata.overview["green"] == true) then
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
				if nodes[nodename]["operator"] then
					for _, operator in ipairs(nodes[nodename]["operator"]) do
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

				check = (not nodes[nodename].noerror) and "✖" or "✔"
				ftable:write_ln(rule.ruleid, nodename, nodedata["note"], passlogic, nodedata.output.value, check)
				if nodedata["noerror"] then
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
	local nodelist = rules.subscription.nodes

	function getEvname(evmatch)
		return evmatch.evname
	end

	function getMatch(evmatch)
		local varlinks = evmatch.subscribed_nodes
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
		-- for _,var in ipairs(evmatch.subscribed_nodes) do
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


function report:queue(rules, iteration)
	local ftable = ft.new()
	local check = ""
	local current_row
	
	function getNodeNames(rules, iteration)
		print(rules.subscriptions)
	end

	getNodeNames(rules, iteration)

	for ruleid, rule in  util.spairs(rules.setting.rules_list.target) do
		for nodename, node in util.spairs(rule) do
			print(node)
		end
		
	end
	--util.dumptable(util.keys(rules.setting.rules_list.target))

end


function report:clear()
	-- clear error statuses, but keep debug data untouched, as they are linked to real rule ongoing data

	-- local nodes = report.debug.nodes
	-- report.debug.noerror = true
	-- for nodename, debugdata in pairs(nodes) do
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
