-- filters/strip-leading-citation.lua
-- If the first block is a paragraph that contains ONLY a citation (optionally wrapped in a link),
-- drop it so it doesn't render under the H1.

local function is_only_citation(inlines)
  -- Accept patterns like: [Link (with citation)] or plain citation
  local hasText = false
  local hasCite = false

  -- Flatten any link content
  local function scan(elems)
    for _, el in ipairs(elems) do
      if el.t == "Cite" then
        hasCite = true
      elseif el.t == "Link" then
        scan(el.content)
      elseif el.t == "Str" or el.t == "Code" or el.t == "Math" then
        hasText = true
      elseif el.t == "Space" or el.t == "SoftBreak" or el.t == "LineBreak" then
        -- ignore whitespace
      else
        -- anything else counts as texty content
        hasText = true
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