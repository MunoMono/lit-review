-- filters/keep-refs.lua
-- Keep only bibliography items whose ids appear in the meta list `keep_refs`
-- (ids look like "ref-KEY"). Everything else in #refs is removed.

local keep = {}

function Meta(m)
  -- collect keys into a set
  if m["keep_refs"] then
    for _, v in ipairs(m["keep_refs"]) do
      if v.t == "Str" then keep["ref-" .. v.text] = true end
    end
  end
end

return {
  {
    Div = function(d)
      if d.identifier ~= "refs" then return nil end
      if next(keep) == nil then return nil end
      local kept = {}
      for _, child in ipairs(d.content) do
        -- each entry is a Div with identifier "ref-KEY"
        if child.t == "Div" and keep[child.identifier] then
          table.insert(kept, child)
        end
      end
      d.content = kept
      return d
    end
  }
}