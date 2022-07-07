local util = require "luci.util"

function last_mdfr_name(varname, rule)
    local varlink = rule.setting[varname]
    local mdfr_names = (varlink.modifier and util.keys(varlink.modifier)) or {}

    return ((#mdfr_names > 0) and mdfr_names[#mdfr_names]) or ""
end
return last_mdfr_name
