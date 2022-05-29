local log = require "applogic.util.log"
local util = require "luci.util"
local pretty = require "applogic.util.prettyjson"

-- Module instantiation
local cjson = require "cjson"

function leading_trailing(str)
    return str:gsub('^%s*', ''):gsub('%s*$', '')
end

function tabular(str)
    return str:gsub("    ", " "):gsub("\t+", "\t"):gsub("%c+", "\n")
end

local report = {}
local debug = {}
debug.rule = {}
debug.varname = ""
debug.init = function(rule)
    debug.rule = rule
    report = rule.report or {}
    return debug
end


function debug:source_bash(command, result, noerror)
    if self.rule.setting[self.varname].source then
        report[self.varname].source = {
            ["type"] = "bash",
            ["code"] = string.format("%s", command),
            ["value"] = string.format("%s", result),
            ["noerror"] = noerror
        }
        report.noerror = noerror and report.noerror
    end
end

function debug:source_ubus(object, method, params, result, noerror, src)
    if self.rule.setting[self.varname].source then
        local src = string.format([[
            source = {
                type = "ubus",
                object = "%s",
                method = "%s",
                params = "%s"
            }
        ]], object, method, util.serialize_json(params))
        local s = tabular(src)
        report[self.varname].source = {
            ["type"] = "ubus",
            ["code"] = src:gsub("    ", " "):gsub("\t+", "\t"):gsub("%c+", "\n"):sub(2,-2),
            ["value"] = pretty(result):gsub("\t", "  "),
            ["noerror"] = noerror
        }

        report.noerror = noerror and report.noerror
    end
end

function debug:source_uci(config, section, option, result, noerror)
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
        report[self.varname].source = {
            ["type"] = "uci",
            ["code"] = src:gsub("    ", " "):gsub("\t+", "\t"):gsub("%c+", "\n"):sub(2,-2),
            ["value"] = result,
            ["noerror"] = noerror
        }
        report.noerror = noerror and report.noerror
    end
end

function debug:input(val)
    local value = val or ""
    if value:len() == 0 then value = "empty" end
    local noerror = (type(value) == "string")
    report[self.varname].input = {
        ["value"] = value:gsub("    ", " "):gsub("\t+", "\t"):gsub("%c+", "\n"),  -- TODO change \t to " " if needed
        ["noerror"] = noerror
    }
    report.noerror = noerror and report.noerror
end

function debug:output(val)
    local value = val or ""
    if value:len() == 0 then value = "empty" end
    local noerror = (type(value) == "string")

    local ok, res = pcall(cjson.decode, value)
    value = ok and pretty(res) or value

    report[self.varname].output = {
        ["value"] = value:gsub("\t", "  "),
        ["noerror"] = noerror
    }
    report.noerror = noerror and report.noerror
end

function debug:modifier(mdf_name, mdf_body, result, noerror)
    if self.rule.setting[self.varname].modifier then
        if not report[self.varname].modifier then
            report[self.varname].modifier = {}
        end

        report[self.varname].modifier[mdf_name] = {
            ["body"] = mdf_body:gsub("\t+", "\t"):gsub("%c+", "\n"),
            ["value"] = result,
            ["noerror"] = noerror
        }
        report.noerror = noerror and report.noerror
    end
end

function debug:modifier_bash(mdf_name, mdf_body, result, noerror)
    local varlink = self.rule.setting[self.varname]
    if varlink.modifier then
        if not report[self.varname].modifier then
            report[self.varname].modifier = {}
        end
        report[self.varname].modifier[mdf_name] = {
            ["body"] = mdf_body:gsub("\t+", "\t"):gsub("%c+", "\n"),
            ["value"] = result.stdout or "",
            ["noerror"] = noerror
        }
        -- Print shell command error together with result, if debug level = INFO
        if varlink.dbg_level and varlink.dbg_level == "INFO" and result.stderr then
            report[self.varname].modifier[mdf_name].value = report[self.varname].modifier[mdf_name].value .. "\n" .. result.stderr
        end
        report.noerror = noerror and report.noerror
    end
end


local metatable = {
	__call = function(table, varname)
        table.varname = varname
        if not report[varname] then
            report[varname] = {}
        end
		return table
	end
}
setmetatable(debug, metatable)

return debug
