-- loads the image.nvim plugin and exposes methods to the python remote plugin
local ok, image = pcall(require, "image")

if not ok then
  vim.api.nvim_echo({ { "[Molten] `image.nvim` not found" } }, true, { err = true })
  return
end

local utils = require("image.utils")

local image_api = {}
local images = {}

-- Inline images whose rows Molten reserves itself (with_virtual_padding = false) get their
-- own anchor extmark, so they follow edits. image.nvim tracks movement with one extmark per
-- (row, col), and all of an output's images share the same row, so only one of them would.
local anchor_ns = vim.api.nvim_create_namespace("molten-image-anchors")
local anchors = {}

local function untrack(id)
  local anchor = anchors[id]
  if anchor then
    pcall(vim.api.nvim_buf_del_extmark, anchor.buf, anchor_ns, anchor.mark)
    anchors[id] = nil
  end
end

local function sync_anchors(buf)
  for id, anchor in pairs(anchors) do
    local img = images[id]
    if not img or not vim.api.nvim_buf_is_valid(anchor.buf) then
      untrack(id)
    elseif anchor.buf == buf then
      local row = vim.api.nvim_buf_get_extmark_by_id(buf, anchor_ns, anchor.mark, {})[1]
      if row and row ~= img.geometry.y then
        img.geometry.y = row
        -- a hidden image keeps the new row and is drawn there when it comes back
        if img.is_rendered then
          img:render()
        end
      end
    end
  end
end

vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
  group = vim.api.nvim_create_augroup("molten-image-anchors", { clear = true }),
  callback = function(ev)
    sync_anchors(ev.buf)
  end,
})

image_api.from_file = function(path, opts)
  if opts.window and opts.window == vim.NIL then
    opts.window = nil
  end
  -- keyed by id, not path: an output's inline and floating images share a path
  local id = opts.id or path
  untrack(id)
  images[id] = image.from_file(path, opts or {})
  -- image.nvim copies these from an earlier image of the same file, so the popup's copy
  -- would keep the inline image's cap
  if images[id] then
    images[id].max_width_window_percentage = opts.max_width_window_percentage
    images[id].max_height_window_percentage = opts.max_height_window_percentage
  end
  -- (a floating output window has no `window` yet and rebuilds its text on every open)
  if images[id] and opts.with_virtual_padding == false and opts.buffer and opts.window then
    anchors[id] = {
      buf = opts.buffer,
      mark = vim.api.nvim_buf_set_extmark(opts.buffer, anchor_ns, opts.y, 0, {}),
    }
  end
  return id
end

image_api.render = function(identifier, geometry)
  geometry = geometry or {}
  local img = images[identifier]
  if not img then
    return
  end

  -- a way to render images in windows when only their buffer is set
  if img.buffer and not img.window then
    local buf_win = vim.fn.getbufinfo(img.buffer)[1].windows
    if #buf_win > 0 then
      img.window = buf_win[1]
    end
  end

  -- only render when the window is visible
  if not img.window or not vim.api.nvim_win_is_valid(img.window) then
    img.window = nil
  end

  if img.window then
    img:render(geometry)
  end
end

image_api.clear = function(identifier)
  if images[identifier] then
    images[identifier]:clear()
  end
end

---hide an image for good. image.nvim keeps every image it has made and re-renders the ones
---tied to a window, so also untie it, or a cleared image can come back
image_api.destroy = function(identifier)
  local img = images[identifier]
  if not img then
    return
  end
  untrack(identifier)
  img:clear()
  img.window = nil
  img.buffer = nil
  images[identifier] = nil
end

image_api.clear_all = function()
  for _, img in pairs(images) do
    img:clear()
  end
end

image_api.move = function(identifier, x, y)
  images[identifier]:move(x, y)
end

---returns the max height this image can be displayed at considering the image size and user's max
---width/height settings. Does not consider max width/height percent values.
image_api.image_size = function(identifier)
  local img = images[identifier]
  if not img then
    return { width = 0, height = 0 }
  end
  local term_size = require("image.utils.term").get_size()
  local gopts = img.global_state.options
  local true_size = {
    width = math.min(img.image_width / term_size.cell_width, gopts.max_width or math.huge),
    height = math.min(img.image_height / term_size.cell_height, gopts.max_height or math.huge),
  }
  local width, height = utils.math.adjust_to_aspect_ratio(
    term_size,
    img.image_width,
    img.image_height,
    true_size.width,
    true_size.height
  )
  return { width = math.ceil(width), height = math.ceil(height) }
end

return { image_api = image_api }
