local log = require "applogic.util.log"
local util = require "luci.util"
local pretty = require "applogic.util.prettyjson"
local cjson = require "cjson"
local report = require "applogic.util.report"

require "applogic.util.wrap_text"


--[[ Example of structure to populate
	variables = {
	    ["varname"] = {
			note = "",
	        source = { code, value, noerror },
	        input = { value, noerror },
	        output = { value, noerror },
	        modifiers = {
	            ["1_func"] = { body, value, noerror }
	        },
			noerror = true,
            order = 1,
	    },
	},
	noerror_rule = true,
]]

local debug = {}
debug.varname = ""
function debug:init(rule)

     if not debug[rule.ruleid] then
         debug[rule.ruleid] = {}
         debug[rule.ruleid].rule = rule
         debug[rule.ruleid].variables = {}
         debug[rule.ruleid].noerror = true
         debug[rule.ruleid].report = report

         rule.debug = debug[rule.ruleid]
    end
    --rule.debug = debug      -- Add populated debug table to the rule table for sharing the data
    --debug.report = report   -- Link to "report" table to access print_var(), print_rule() methods

end

function debug:set_noerrors(varl, noerror)
    local asvarattr = varl
    local asruleattr = debug[debug.ruleid]
    asvarattr.noerror = noerror and asvarattr.noerror
    asruleattr.noerror = noerror and asruleattr.noerror
end


function debug:note(val)
    local value = val or ""
    local dvlink = debug[debug.ruleid].variables[debug.varname]
    if value:len() == 0 then value = "empty" end
    local noerror = (type(value) == "string")
    value = value:gsub("%s+\n", " \n"):gsub("\n%s+", "\n")
    value = value:trim()

    value = wrap_text(value)


    -- if value:len() > 20  then
    --     local pos = value:find(" ", 39)
    --     value = value:sub(1,pos-1) .. "\n" .. value:sub(pos,-1)
    -- end

    dvlink.note = value
    debug:set_noerrors(dvlink, noerror)
end

function debug:order()
    local dvlink = debug[debug.ruleid].variables[debug.varname]
    dvlink.order = debug[debug.ruleid].rule.setting[self.varname].order
end

function debug:source_bash(command, result, noerror)
    local dvlink = debug[debug.ruleid].variables[debug.varname]
    if debug[debug.ruleid].rule.setting[self.varname].source then
        dvlink.source = {
            ["type"] = "bash",
            ["code"] = string.format("%s", command),
            ["value"] = string.format("%s", result),
            ["noerror"] = noerror
        }
        debug:set_noerrors(dvlink, noerror)
    end
end

function debug:source_ubus(object, method, params, result, noerror, src)
    local dvlink = debug[debug.ruleid].variables[debug.varname]
    local rvlink = debug[debug.ruleid].rule.setting[self.varname]

    if rvlink.source then
        local src = string.format([[
            source = {
                type = "ubus",
                object = "%s",
                method = "%s",
                params = "%s",
            }
        ]], object, method, util.serialize_json(params))
        dvlink.source = {
            ["type"] = "ubus",
            ["code"] = src:gsub("    ", " "):gsub("\t+", "\t"):gsub("%c+", "\n"):sub(2,-2),
            ["value"] = pretty(result):gsub("\t", "  "),
            ["noerror"] = noerror
        }

        debug:set_noerrors(dvlink, noerror)
    end
end

function debug:source_uci(confdvlinkig, section, option, result, noerror)
    local dvlink = debug[debug.ruleid].variables[debug.varname]
    if debug[debug.ruleid].rule.setting[self.varname].source then
        local sec = ((type(section) == "table") and util.serialize_json(section)) or section
        local src = string.format([[
            source = {
                type = "uci",
                config = "%s",
                section = "%s",
                option = "%s"
            }
        ]], config, section, (option or ""))
        dvlink.source = {
            ["type"] = "uci",
            ["code"] = src:gsub("    ", " "):gsub("\t+", "\t"):gsub("%c+", "\n"):sub(2,-2),
            ["value"] = result,
            ["noerror"] = noerror
        }
        debug:set_noerrors(dvlink, noerror)
    end
end

function debug:input(val)
    local dvlink = debug[debug.ruleid].variables[debug.varname]
    local value = tostring(val) or ""
    if value:len() == 0 then value = "empty" end
    local noerror = (type(value) == "string")
    dvlink.input = {
        ["value"] = value:gsub("    ", " "):gsub("\t+", "\t"):gsub("%c+", "\n"),  -- TODO change \t to " " if needed
        ["noerror"] = noerror
    }
    debug:set_noerrors(dvlink, noerror)
end

function debug:output(val)
    local dvlink = debug[debug.ruleid].variables[debug.varname]
    local value = val or ""
    if value:len() == 0 then value = "empty" end
    local noerror = (type(value) == "string")

    local ok, res = pcall(cjson.decode, value)
    
    if(debug.varname == "title") then
        value = ok and pretty(res) or value
    else
        value = ok and pretty(res) or wrap_text(value)
    end


    dvlink.output = {
        ["value"] = value:gsub("\t", "  "),
        ["noerror"] = noerror
    }
    debug:set_noerrors(dvlink, noerror)
end

function debug:modifier(mdf_name, mdf_body, result, noerror)
    local dvlink = debug[debug.ruleid].variables[debug.varname]
    if debug[debug.ruleid].rule.setting[self.varname].modifier then
        if not dvlink.modifier then
            dvlink.modifier = {}
        end

        mdf_body = mdf_body:gsub("\t+", "\t"):gsub("%c+", "\n")
        mdf_body = wrap_text(mdf_body)

        if (type(result) == "string" and result:len() == 0) then result = "empty" end
        if (type(result) == "table") then result = pretty(result):gsub("\t", "  ") end

        dvlink.modifier[mdf_name] = {
            ["body"] = mdf_body,
            ["value"] = result,
            ["noerror"] = noerror
        }
        debug:set_noerrors(dvlink, noerror)
    end
end

function debug:modifier_bash(mdf_name, mdf_body, result, noerror)
    local dvlink = debug[debug.ruleid].variables[debug.varname]
    if not dvlink.modifier then
        dvlink.modifier = {}
    end
    dvlink.modifier[mdf_name] = {
        ["body"] = mdf_body:gsub("\t+", "\t"):gsub("%c+", "\n"),
        ["value"] = result.stdout or "",
        ["noerror"] = noerror
    }

    --log("DDD", dvlink)

    -- Print shell command error together with result
    if result.stderr then
        dvlink.modifier[mdf_name].value = result.stderr .. "\n" .. dvlink.modifier[mdf_name].value
    end
    debug:set_noerrors(dvlink, noerror)
end


local metatable = {
	__call = function(table, varname, rule)
        table.varname = varname
        local ruleid = rule.ruleid
        table.ruleid = ruleid
        table:init(rule)
        if not debug[ruleid].variables[varname] then
            debug[ruleid].variables[varname] = {}
            debug[ruleid].variables[varname].noerror = true
        end

		return table
	end
}
setmetatable(debug, metatable)

return debug
