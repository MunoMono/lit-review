-- filters/citations-in-lists.lua
-- No-op visitor that forces Pandoc to traverse all inlines/blocks,
-- including list items, before citeproc runs.
return {
  {
    Para = function(el) return el end,
    BulletList = function(el) return el end,
    OrderedList = function(el) return el end,
    Plain = function(el) return el end,
  }
}