local util = require "luci.util"
local log = require "applogic.util.log"
local pretty = require "applogic.util.prettyjson"


function init(varname, mdf_name, modifier, rule)
    local debug
    if rule.debug_mode.enabled then debug = require "applogic.var.debug" end

    local varlink = rule.setting[varname] or {}
    local vars = modifier.vars or {}
    local params, name = {}, ''
    local result = {}
    local noerror = true

    for i=1, #vars do
        name = vars[i]
        rule.setting[name] = util.clone(rule.default_setting[name], true)
    end

    if rule.debug_mode.enabled then
        result.stdout = pretty(params):gsub("\t", "  ")
        debug(varname, rule):modifier(mdf_name, pretty(vars):gsub("\t", "  "), result.stdout, noerror)
    end
end

return init
