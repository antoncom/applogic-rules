function wrap_text(str, limit, indent, indent1)
  indent = indent or ""
  indent1 = indent1 or indent

  limit = limit or 70
  -- Also, prevent too long string without any spaces
  -- by adding a space after each 70 symbol
  local s = str:gsub('%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S%S','%1 ')
  local here = 1-#indent1

  return indent1..s:gsub("(%s+)()(%S+)()",
        function(sp, st, word, fi)
            if fi-here > limit then
                here = st - #indent
                return "\n"..indent..word
            end
        end)
end
