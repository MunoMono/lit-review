-- filters/sentence-case-title.lua
-- Force Sentence case for the document title (YAML `title:` only).
-- Example: "New Design Knowledge and the Fifth Order of Design"
--   ->     "New design knowledge and the fifth order of design"
--
-- Notes:
--  - Restores common acronyms (AI, LLM, UK, USA, EU, PhD, RCA, NLP).
--  - Does not attempt to detect proper nouns beyond the acronym list.

local utils = require 'pandoc.utils'

local ACRONYMS = {
  "AI","LLM","NLP","UK","USA","EU","PhD","RCA"
}

local function sentence_case(s)
  if not s or s == "" then return s end
  -- lower everything
  local lowered = s:lower()
  -- uppercase first alphabetical letter
  lowered = lowered:gsub("^%s*(%a)", function(c) return c:upper() end, 1)

  -- restore known acronyms
  for _, ac in ipairs(ACRONYMS) do
    local pat = "(%f[%a])" .. ac:lower() .. "(%f[%A])"
    lowered = lowered:gsub(pat, function(a,b) return a .. ac .. b end)
  end

  -- OPTIONAL: if you want to also uppercase the first letter after a colon
  -- (uncomment next line)
  -- lowered = lowered:gsub("(:%s*)(%l)", function(pfx,c) return pfx .. c:upper() end, 1)

  return lowered
end

return {
  Meta = function(meta)
    if meta.title then
      -- stringify current title to plain text, apply sentence case, set back as MetaString
      local t = utils.stringify(meta.title)
      meta.title = pandoc.MetaString(sentence_case(t))
    end
    return meta
  end
}