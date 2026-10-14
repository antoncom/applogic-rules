-- Режим "applogic debug overview": вычисление цвета строки узла в общей отладочной таблице.
--
-- В правиле описывается таблица overview, ключ - имя узла, значение - таблица цветов:
--
--     local overview = {
--         ["signal"] = { ["yellow"] = function(nodes) return <true/false> end },
--         ["switch"] = { ["red"]    = function(nodes) return <true/false> end },
--     }
--     self:follow("signal"):debug(overview)
--
-- nodes - то же окно на значения узлов правила, что получают операторы ([func], [skip] и т.д.).
-- Цвет применяется, если функция вернула true. Приоритет: red > yellow > green.
-- Если функция упала с ошибкой - строка помечается ✖, текст ошибки выводится в колонке NOTES.
-- Если для узла задано не таблица цветов (например, true) - узел выводится без подсветки.
--
-- Для совместимости поддерживаются и старые строковые условия вида [[ return ($node == "true") ]],
-- но со значениями-таблицами они не работают, поэтому используйте функции.

local func_nodes_builder = require "applogic.util.func_nodes_builder"
local substitute = require "applogic.util.substitute"
local pcallchunk = require "applogic.util.pcallchunk"

local PRIORITY = { "red", "yellow", "green" }

local function eval(rule, cond)
    if type(cond) == "function" then
        local ok, res = pcall(cond, func_nodes_builder:make_nodes(rule))
        if not ok then return false, tostring(res) end
        return res == true
    elseif type(cond) == "string" then
        local ok, res = pcallchunk(substitute(rule, cond, true))
        if not ok then return false, "lua chunk error" end
        return res == true
    elseif type(cond) == "boolean" then
        return cond
    end
    return false, "unsupported condition type: " .. type(cond)
end

local overview = {}

-- Регистрирует узел в overview-таблице правила и вычисляет его цвет на текущей итерации
function overview.node(rule, nodename, spec)
    if not (rule.debug and rule.debug.nodes and rule.debug.nodes[nodename]) then return end

    local color, err
    if type(spec) == "table" then
        for _, c in ipairs(PRIORITY) do
            if spec[c] ~= nil then
                local hit, e = eval(rule, spec[c])
                if e then err = (err and (err .. "\n") or "") .. c .. ": " .. e end
                if hit and not color then color = c end
            end
        end
    end

    rule.debug.nodes[nodename].overview = { color = color, error = err }
    rule.debug.overviewed = rule.debug.overviewed or {}
    rule.debug.overviewed[nodename] = true
end

return overview
