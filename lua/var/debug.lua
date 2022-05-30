local log = require "applogic.util.log"
local util = require "luci.util"
local pretty = require "applogic.util.prettyjson"
local cjson = require "cjson"
local report = require "applogic.util.report"

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
debug.init = function(rule)
    debug.rule = rule
    if not debug.variables then
        debug.variables = {}
        debug.noerror_rule = true
    end
    rule.debug = debug      -- Add populated debug table to the rule table for sharing the data
    debug.report = report   -- Link to "report" table to access print_var(), print_rule() methods
    return debug
end

function debug:set_noerrors(varl, noerror)
    local asvarattr = varl
    local asruleattr = self
    asvarattr.noerror = noerror and asvarattr.noerror
    asruleattr.noerror = noerror and asruleattr.noerror
end


function debug:note(val)
    local value = val or ""
    local dvlink = debug.variables[debug.varname]
    if value:len() == 0 then value = "empty" end
    local noerror = (type(value) == "string")
    dvlink.note = value
    debug:set_noerrors(dvlink, noerror)
end

function debug:order()
    local dvlink = debug.variables[debug.varname]
    dvlink.order = debug.rule.setting[self.varname].order
end

function debug:source_bash(command, result, noerror)
    local dvlink = debug.variables[debug.varname]
    if self.rule.setting[self.varname].source then
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
    local dvlink = debug.variables[debug.varname]
    if self.rule.setting[self.varname].source then
        local src = string.format([[
            source = {
                type = "ubus",
                object = "%s",
                method = "%s",
                params = "%s"
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
    local dvlink = debug.variables[debug.varname]
    if self.rule.setting[self.varname].source then
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
    local dvlink = debug.variables[debug.varname]
    local value = val or ""
    if value:len() == 0 then value = "empty" end
    local noerror = (type(value) == "string")
    dvlink.input = {
        ["value"] = value:gsub("    ", " "):gsub("\t+", "\t"):gsub("%c+", "\n"),  -- TODO change \t to " " if needed
        ["noerror"] = noerror
    }
    debug:set_noerrors(dvlink, noerror)
end

function debug:output(val)
    local dvlink = debug.variables[debug.varname]
    local value = val or ""
    if value:len() == 0 then value = "empty" end
    local noerror = (type(value) == "string")

    local ok, res = pcall(cjson.decode, value)
    value = ok and pretty(res) or value

    dvlink.output = {
        ["value"] = value:gsub("\t", "  "),
        ["noerror"] = noerror
    }
    debug:set_noerrors(dvlink, noerror)
end

function debug:modifier(mdf_name, mdf_body, result, noerror)
    local dvlink = debug.variables[debug.varname]
    if self.rule.setting[self.varname].modifier then
        if not dvlink.modifier then
            dvlink.modifier = {}
        end

        dvlink.modifier[mdf_name] = {
            ["body"] = mdf_body:gsub("\t+", "\t"):gsub("%c+", "\n"),
            ["value"] = result,
            ["noerror"] = noerror
        }
        debug:set_noerrors(dvlink, noerror)
    end
end

function debug:modifier_bash(mdf_name, mdf_body, result, noerror)
    local dvlink = debug.variables[debug.varname]
    if dvlink.modifier then
        if not dvlink.modifier then
            dvlink.modifier = {}
        end
        dvlink.modifier[mdf_name] = {
            ["body"] = mdf_body:gsub("\t+", "\t"):gsub("%c+", "\n"),
            ["value"] = result.stdout or "",
            ["noerror"] = noerror
        }

        --log("DDD", dvlink)

        -- Print shell command error together with result, if debug level = INFO
        if debug.rule.debug.level and debug.rule.debug.level == "INFO" and result.stderr then
            dvlink.modifier[mdf_name].value = dvlink.modifier[mdf_name].value .. "\n" .. result.stderr
        end
        debug:set_noerrors(dvlink, noerror)
    end
end


local metatable = {
	__call = function(table, varname)
        table.varname = varname
        if not debug.variables[varname] then
            debug.variables[varname] = {
                noerror = true
            }
        end
		return table
	end
}
setmetatable(debug, metatable)

return debug
