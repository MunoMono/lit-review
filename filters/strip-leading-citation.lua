-- filters/strip-leading-citation.lua
-- If the first block is a paragraph that contains ONLY a citation (optionally wrapped in a link),
-- drop it so it doesn't render under the H1.

local function is_only_citation(inlines)
  local hasText, hasCite = false, false

  local function scan(elems)
    for _, el in ipairs(elems) do
      if el.t == "Cite" then
        hasCite = true
      elseif el.t == "Link" then
        scan(el.content)        -- inspect link contents
      elseif el.t == "Str" or el.t == "Code" or el.t == "Math" then
        hasText = true
      elseif el.t == "Space" or el.t == "SoftBreak" or el.t == "LineBreak" then
        -- ignore whitespace
      else
        hasText = true          -- any other content counts as text
      end
    end
  end

  scan(inlines)
  return hasCite and not hasText
end

return {
  Pandoc = function(doc)
    if #doc.blocks == 0 then return doc end
    local first = doc.blocks[1]
    if first.t == "Para" and is_only_citation(first.content) then
      table.remove(doc.blocks, 1)
    end
    return doc
  end
}