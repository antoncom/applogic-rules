local util = require "luci.util"

local ft = require "fort"

util.dumptable(ft)

ft.ANY_ROW = 4294967295
ft.ANY_COLUMN = 4294967295

local function print_table_with_styles(style, name)
    -- Just create a table with some content
    local ftable = ft.new()
    ftable:set_cell_prop(ft.ANY_ROW, 1, ft.CPROP_TEXT_ALIGN, ft.ALIGNED_LEFT)
    ftable:set_cell_prop(ft.ANY_ROW, 2, ft.CPROP_TEXT_ALIGN, ft.ALIGNED_LEFT)
    ftable:set_cell_prop(1, ft.ANY_COLUMN, ft.CPROP_ROW_TYPE, ft.ROW_HEADER)

    ftable:write_ln("Variable", "timer", "#12")
    ftable:add_separator()
    ftable:write_ln("input", "0", "")
    ftable:write_ln("output", "10", "")
    ftable:write_ln("source", [[
type = "bash",
command = "uci show wimark | tr -d '"' | tr -d "'"  | grep 'host' | awk -F'=' '{print $2}'"]], "")
    ftable:write_ln("modifiers:", "", "")
    ftable:write_ln("[1_func]", [[
if ( ("$timer" == "") or (tonumber("$timer") <= 0) ) then
    return "$check_every"
else
    return tostring((tonumber("$timer") - 1))
end ]], "")

    ftable:set_cell_span(5, 1, 3)

    -- Setup border style
    ftable:set_border_style(style)
    -- Print ftable
    print(string.format("%s style:\n\n%s\n\n", name, tostring(ftable)))
end

local function print_table_with_different_styles()
    local function print_style(name) print_table_with_styles(ft[name], name) end
    print_style("BOLD2_STYLE")
end

print_table_with_different_styles()
