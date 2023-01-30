local helpers = dofile('tests/helpers.lua')

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.mini_load('basics', config) end
local unload_module = function() child.mini_unload('basics') end
local reload_module = function(config) unload_module(); load_module(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
--stylua: ignore end

-- Output test set ============================================================
T = new_set({
  hooks = {
    pre_case = child.setup,
    post_once = child.stop,
  },
})

-- Unit tests =================================================================
T['setup()'] = new_set()

T['setup()']['creates side effects'] = function()
  load_module()

  -- Global variable
  eq(child.lua_get('type(_G.MiniBasics)'), 'table')
end

T['setup()']['creates `config` field'] = function()
  load_module()

  eq(child.lua_get('type(_G.MiniBasics.config)'), 'table')

  -- Check default values
  local expect_config = function(field, value) eq(child.lua_get('MiniBasics.config.' .. field), value) end

  -- Check default values
  expect_config('options.basic', true)
  expect_config('options.extra_ui', false)
  expect_config('options.win_borders', 'default')
  expect_config('mappings.basic', true)
  expect_config('mappings.option_toggle_prefix', [[\]])
  expect_config('mappings.windows', false)
  expect_config('mappings.move_with_alt', false)
  expect_config('autocommands.basic', true)
  expect_config('autocommands.relnum_in_visual_mode', false)
end

T['setup()']['respects `config` argument'] = function()
  load_module({ options = { basic = false } })
  eq(child.lua_get('MiniBasics.config.options.basic'), false)
end

T['setup()']['validates `config` argument'] = function()
  local expect_config_error = function(config, name, target_type)
    expect.error(load_module, vim.pesc(name) .. '.*' .. vim.pesc(target_type), config)
  end

  expect_config_error('a', 'config', 'table')
  expect_config_error({ options = 'a' }, 'options', 'table')
  expect_config_error({ options = { basic = 1 } }, 'options.basic', 'boolean')
  expect_config_error({ options = { extra_ui = 1 } }, 'options.extra_ui', 'boolean')
  expect_config_error({ options = { win_borders = 1 } }, 'options.win_borders', 'string')
  expect_config_error({ mappings = 'a' }, 'mappings', 'table')
  expect_config_error({ mappings = { basic = 1 } }, 'mappings.basic', 'boolean')
  expect_config_error({ mappings = { option_toggle_prefix = 1 } }, 'mappings.option_toggle_prefix', 'string')
  expect_config_error({ mappings = { windows = 1 } }, 'mappings.windows', 'boolean')
  expect_config_error({ mappings = { move_with_alt = 1 } }, 'mappings.move_with_alt', 'boolean')
  expect_config_error({ autocommands = 'a' }, 'autocommands', 'table')
  expect_config_error({ autocommands = { basic = 1 } }, 'autocommands.basic', 'boolean')
  expect_config_error({ autocommands = { relnum_in_visual_mode = 1 } }, 'autocommands.relnum_in_visual_mode', 'boolean')
end

T['toggle_diagnostic()'] = new_set()

T['toggle_diagnostic()']['works'] = function()
  local toggle_diagnostic = function() return child.lua_get('MiniBasics.toggle_diagnostic()') end
  child.lua([[vim.diagnostic.enable = function() vim.b.diag_status = 'enabled' end]])
  child.lua([[vim.diagnostic.disable = function() vim.b.diag_status = 'disabled' end]])

  load_module()

  -- Should disable on per-buffer basis
  local buf_id_one = child.api.nvim_get_current_buf()
  local buf_id_two = child.api.nvim_create_buf(true, false)

  child.api.nvim_set_current_buf(buf_id_one)
  eq(child.b.diag_status, vim.NIL)
  eq(toggle_diagnostic(), 'nodiagnostic')
  eq(child.b.diag_status, 'disabled')

  child.api.nvim_set_current_buf(buf_id_two)
  eq(child.b.diag_status, vim.NIL)
  eq(toggle_diagnostic(), 'nodiagnostic')
  eq(child.b.diag_status, 'disabled')

  child.api.nvim_set_current_buf(buf_id_one)
  eq(child.b.diag_status, 'disabled')
  eq(toggle_diagnostic(), '  diagnostic')
  eq(child.b.diag_status, 'enabled')

  child.api.nvim_set_current_buf(buf_id_two)
  eq(child.b.diag_status, 'disabled')
  eq(toggle_diagnostic(), '  diagnostic')
  eq(child.b.diag_status, 'enabled')
end

-- Integration tests ==========================================================
T['Options'] = new_set()

T['Options']['work'] = function()
  -- Basic options (should be set by default)
  eq(child.g.mapleader, vim.NIL)
  eq(child.o.termguicolors, false)
  eq(child.o.number, false)
  eq(child.o.signcolumn, 'auto')
  eq(child.o.fillchars, '')

  -- Extra options (should not be set by default)
  eq(child.o.pumblend, 0)

  load_module()

  eq(child.g.mapleader, ' ')
  eq(child.o.termguicolors, true)
  eq(child.o.number, true)
  eq(child.o.signcolumn, 'yes')
  eq(child.o.fillchars, 'eob: ')

  eq(child.o.pumblend, 0)
end

T['Options']['do not override manually set options'] = function()
  -- Shouldn't modify options manually set to non-default value
  child.g.mapleader = ';'
  child.o.signcolumn = 'no'
  child.o.pumblend = 50

  -- Shouldn't modify option manually set to default value
  child.o.number = false
  child.o.list = false

  load_module({ options = { basic = true, extra_ui = true } })

  eq(child.g.mapleader, ';')
  eq(child.o.signcolumn, 'no')
  eq(child.o.pumblend, 50)
  eq(child.o.number, false)
  eq(child.o.list, false)
end

T['Options']['respect `config.options.basic`'] = function()
  eq(child.g.mapleader, vim.NIL)
  eq(child.o.termguicolors, false)
  eq(child.o.number, false)
  eq(child.o.signcolumn, 'auto')

  load_module({ options = { basic = false } })

  eq(child.g.mapleader, vim.NIL)
  eq(child.o.termguicolors, false)
  eq(child.o.number, false)
  eq(child.o.signcolumn, 'auto')
end

T['Options']['respect `config.options.extra_ui`'] = function()
  eq(child.o.pumblend, 0)
  eq(child.o.list, false)

  load_module({ options = { extra_ui = true } })

  eq(child.o.pumblend, 10)
  eq(child.o.list, true)
end

T['Options']['respect `config.options.win_borders`'] = function()
  eq(child.o.fillchars, '')

  load_module({ options = { basic = false, win_borders = 'double' } })

  local ref_value
  if child.fn.has('nvim-0.7') == 1 then
    ref_value = 'horiz:═,horizdown:╦,horizup:╩,vert:║,verthoriz:╬,vertleft:╣,vertright:╠'
  else
    ref_value = 'vert:║'
  end
  eq(child.o.fillchars, ref_value)
end

T['Mappings'] = new_set()

T['Mappings']['work'] = function()
  expect.match(child.cmd_capture('nmap go'), 'No mapping')

  load_module()

  expect.match(child.cmd_capture('nmap go'), 'go.*call')
end

T['Mappings']['do not override manually created mappings'] = function()
  child.api.nvim_set_keymap('n', 'j', 'aaaaa', { noremap = true })
  child.api.nvim_set_keymap('n', ',s', 'bbbbb', { noremap = true })
  child.api.nvim_set_keymap('n', '<C-h>', 'ccccc', { noremap = true })
  child.api.nvim_set_keymap('n', '<M-h>', 'ddddd', { noremap = true })

  load_module({ mappings = { basic = true, option_toggle_prefix = ',', windows = true, move_with_alt = true } })

  expect.match(child.cmd_capture('nmap j'), 'aaaaa')
  expect.match(child.cmd_capture('nmap ,s'), 'bbbbb')
  expect.match(child.cmd_capture('nmap <C-h>'), 'ccccc')
  expect.match(child.cmd_capture('nmap <M-h>'), 'ddddd')
end

T['Mappings']['Basic'] = new_set()

T['Mappings']['Basic']['can be disabled'] = function()
  expect.match(child.cmd_capture('nmap go'), 'No mapping')

  load_module({ mappings = { basic = false } })

  expect.match(child.cmd_capture('nmap go'), 'No mapping')
end

T['Mappings']['Basic']['j/k'] = function()
  local validate = function()
    -- Goes by visible lines without `[count]`
    set_cursor(1, 0)
    type_keys('jj')
    eq(get_cursor(), { 1, 24 })
    type_keys('k')
    eq(get_cursor(), { 1, 12 })

    -- Goes by usual lines with `[count]`
    set_cursor(1, 0)
    type_keys('1j')
    eq(get_cursor(), { 2, 0 })
    type_keys('1k')
    eq(get_cursor(), { 1, 0 })
  end

  load_module()

  child.o.number = false
  child.o.signcolumn = 'no'
  child.o.wrap = true
  child.set_size(10, 12)
  set_lines({ string.rep('a', 48), 'bbb' })

  -- Normal mode
  child.ensure_normal_mode()
  validate()

  -- Visual mode
  set_cursor(1, 0)
  type_keys('v')
  eq(child.fn.mode(), 'v')
  child.ensure_normal_mode()
end

T['Mappings']['Basic']['go'] = function()
  load_module()

  -- Should add empty line(s) below with cursor staying on line
  set_lines({ 'aaa' })
  set_cursor(1, 1)

  type_keys('go')
  eq(get_lines(), { 'aaa', '' })
  eq(get_cursor(), { 1, 1 })

  -- Should respect `[count]`
  type_keys('2go')
  eq(get_lines(), { 'aaa', '', '', '' })
  eq(get_cursor(), { 1, 1 })
end

T['Mappings']['Basic']['gO'] = function()
  load_module()

  -- Should add empty line(s) above with cursor staying on line
  set_lines({ 'aaa' })
  set_cursor(1, 1)

  type_keys('gO')
  eq(get_lines(), { '', 'aaa' })
  eq(get_cursor(), { 2, 1 })

  -- Should respect `[count]`
  type_keys('2gO')
  eq(get_lines(), { '', '', '', 'aaa' })
  eq(get_cursor(), { 4, 1 })
end

T['Mappings']['Basic']['gy'] = function()
  load_module()

  set_lines({ 'xxx' })
  type_keys('"+yiw')
  eq(child.fn.getreg('+'), 'xxx')

  -- Should copy to `+` register
  set_lines({ 'aaa' })
  set_cursor(1, 0)
  type_keys('gyiw')
  eq(child.fn.getreg('+'), 'aaa')

  -- Should also work in Visual mode
  set_lines({ 'bbb' })
  set_cursor(1, 0)
  type_keys('viwgy')
  eq(child.fn.getreg('+'), 'bbb')
end

T['Mappings']['Basic']['gp'] = function()
  load_module()

  -- Has problems with CI testing, so test mapping themselves. Should be enough
  -- as they are quite basic.
  local created_mappings = {}

  local normal_keymaps = child.api.nvim_get_keymap('n')
  for _, keymap in ipairs(normal_keymaps) do
    if keymap.lhs == 'gy' then
      table.insert(created_mappings, 'n_gy')
      eq(keymap.rhs, '"+y')
    end
    if keymap.lhs == 'gp' then
      table.insert(created_mappings, 'n_gp')
      eq(keymap.rhs, '"+p')
    end
  end

  local visual_keymaps = child.api.nvim_get_keymap('x')
  for _, keymap in ipairs(visual_keymaps) do
    if keymap.lhs == 'gy' then
      table.insert(created_mappings, 'x_gy')
      eq(keymap.rhs, '"+y')
    end
    if keymap.lhs == 'gp' then
      table.insert(created_mappings, 'x_gp')
      -- Should use `P` to not cut visual selection in `""` register
      eq(keymap.rhs, '"+P')
    end
  end

  table.sort(created_mappings)
  eq(created_mappings, { 'n_gp', 'n_gy', 'x_gp', 'x_gy' })
end

T['Mappings']['Basic']['gV'] = function()
  local validate_cur_selection = function(ref_selection)
    eq({ { child.fn.line('v'), child.fn.col('v') }, { child.fn.line('.'), child.fn.col('.') } }, ref_selection)
  end
  load_module()

  -- Should reselect previously pasted or yanked text

  -- Charwise mode
  set_lines({ 'aaa', 'bbb', 'ccc' })
  set_cursor(1, 0)
  type_keys('yiw')
  set_cursor(2, 0)
  type_keys('P')

  -- - Result selection should not depend on latest Visual selection type
  set_cursor(1, 0)
  type_keys('V', '<Esc>')

  type_keys('gV')
  validate_cur_selection({ { 2, 1 }, { 2, 3 } })
  eq(child.fn.mode(), 'v')

  child.ensure_normal_mode()

  -- Linewise mode
  set_lines({ 'aaa', 'bbb', 'ccc' })
  set_cursor(1, 0)
  type_keys('yy', 'p')

  -- - Result selection should not depend on latest Visual selection type
  set_cursor(1, 0)
  type_keys('viw', '<Esc>')

  type_keys('gV')
  validate_cur_selection({ { 2, 1 }, { 2, 3 } })
  eq(child.fn.mode(), 'V')

  child.ensure_normal_mode()

  -- Blockwise mode
  set_lines({ 'aaa', 'bbb', 'ccc' })
  set_cursor(1, 0)
  type_keys('<C-v>ly')
  set_cursor(2, 0)
  type_keys('P')

  -- - Result selection should not depend on latest Visual selection type
  set_cursor(1, 0)
  type_keys('viw', '<Esc>')

  type_keys('gV')
  validate_cur_selection({ { 2, 1 }, { 2, 2 } })
  eq(child.fn.mode(), '\22')
end

T['Mappings']['Basic']['g/'] = function()
  load_module()

  -- Should search inside visual selection
  set_lines({ 'abc', 'abc', 'abc' })
  set_cursor(1, 0)
  type_keys('Vj', 'g/', 'a<CR>')

  eq(get_cursor(), { 1, 0 })
  type_keys('n')
  eq(get_cursor(), { 2, 0 })
  -- Should not recognize match outside visual selection
  type_keys('n')
  eq(get_cursor(), { 1, 0 })
end

T['Mappings']['Basic']['*/#'] = function()
  load_module()

  -- Should work just like in Normal mode but for visual selection and even
  -- with bad characters present

  -- *
  set_lines({ [[aa?/\bb]], 'aa', [[aa?/\bb]], 'aa', [[aa?/\bb]] })
  set_cursor(1, 0)
  type_keys('v$h', '*')

  eq(get_cursor(), { 3, 0 })
  type_keys('n')
  eq(get_cursor(), { 5, 0 })
  type_keys('n')
  eq(get_cursor(), { 1, 0 })
  type_keys('n')
  eq(get_cursor(), { 3, 0 })

  child.cmd('nohlsearch')
  child.ensure_normal_mode()

  -- #
  set_lines({ [[aa?/\bb]], 'aa', [[aa?/\bb]], 'aa', [[aa?/\bb]] })
  set_cursor(1, 0)
  type_keys('v$h', '#')

  eq(get_cursor(), { 5, 0 })
  type_keys('n')
  eq(get_cursor(), { 3, 0 })
  type_keys('n')
  eq(get_cursor(), { 1, 0 })
  type_keys('n')
  eq(get_cursor(), { 5, 0 })
end

T['Mappings']['Basic']['<C-s>'] = function()
  local test_file_path = 'tests/ctrl-s.txt'
  MiniTest.finally(function() child.fn.delete(test_file_path) end)

  load_module()

  child.cmd('write ' .. test_file_path)

  -- Should save in Normal mode
  eq(child.bo.modified, false)
  set_lines({ 'aaa' })
  eq(child.bo.modified, true)

  type_keys('<C-s>')
  eq(child.bo.modified, false)
  eq(child.fn.mode(), 'n')

  -- Should save in Insert mode and leave in Normal mode
  eq(child.bo.modified, false)
  set_lines({ 'aaa' })
  set_cursor(1, 0)
  child.cmd('startinsert')
  eq(child.bo.modified, true)
  eq(child.fn.mode(), 'i')

  type_keys('<C-s>')
  eq(child.bo.modified, false)
  eq(child.fn.mode(), 'n')

  -- Should save in Visual mode and leave in Normal mode
  eq(child.bo.modified, false)
  set_lines({ 'aaa' })
  set_cursor(1, 0)
  type_keys('v')
  eq(child.bo.modified, true)
  eq(child.fn.mode(), 'v')

  type_keys('<C-s>')
  eq(child.bo.modified, false)
  eq(child.fn.mode(), 'n')
end

T['Mappings']['Basic']['<C-z>'] = function()
  load_module()
  child.o.spell = true

  -- Should correct latest misspelled
  set_lines({ 'Helo to arl the wolld!' })
  set_cursor(1, 18)
  type_keys('<C-z>')
  eq(get_lines(), { 'Helo to arl the world!' })

  -- Should respect `[count]`
  set_lines({ 'Helo to arl the wolld!' })
  set_cursor(1, 18)
  type_keys('2<C-z>')
  eq(get_lines(), { 'Helo to all the wolld!' })

  -- Should also work in Insert mode with separate undo block
  set_lines({ 'Helo ' })
  type_keys('A', 'to all')

  type_keys('<C-z>')
  eq(get_lines(), { 'Hello to all' })
  eq(child.fn.mode(), 'i')

  type_keys(' the world!', '<Esc>')
  eq(get_lines(), { 'Hello to all the world!' })
  eq(child.fn.mode(), 'n')

  type_keys('u')
  eq(get_lines(), { 'Hello to all' })
  type_keys('u')
  eq(get_lines(), { 'Helo to all' })
  type_keys('u')
  eq(get_lines(), { 'Helo ' })
end

T['Mappings']['Toggle options'] = new_set()

T['Mappings']['Toggle options']['work'] = function()
  -- NOTE: these mappings should also give feedback about new option values.
  -- But there doesn't seem to be a way of testing it without screenshots
  -- (which is not worth it).
  local validate = function(keys, option, before, after)
    eq(child.o[option], before)
    type_keys(keys)
    eq(child.o[option], after)
    type_keys(keys)
    eq(child.o[option], before)
  end

  child.g.mapleader = ' '
  load_module({ options = { basic = false } })

  validate([[\b]], 'background', 'dark', 'light')
  validate([[\c]], 'cursorline', false, true)
  validate([[\C]], 'cursorcolumn', false, true)
  -- \d should toggle diagnostic
  -- \h should almost toggle 'hlsearch'
  validate([[\i]], 'ignorecase', false, true)
  validate([[\l]], 'list', false, true)
  validate([[\n]], 'number', false, true)
  validate([[\r]], 'relativenumber', false, true)
  validate([[\s]], 'spell', false, true)
  validate([[\w]], 'wrap', true, false)
end

T['Mappings']['Toggle options']['works with diagnostic'] = function()
  child.lua([[vim.diagnostic.enable = function() vim.b.diag_status = 'enabled' end]])
  child.lua([[vim.diagnostic.disable = function() vim.b.diag_status = 'disabled' end]])

  load_module()

  -- Should disable on per-buffer basis
  local buf_id_one = child.api.nvim_get_current_buf()
  local buf_id_two = child.api.nvim_create_buf(true, false)

  child.api.nvim_set_current_buf(buf_id_one)
  eq(child.b.diag_status, vim.NIL)
  type_keys([[\d]])
  eq(child.b.diag_status, 'disabled')

  child.api.nvim_set_current_buf(buf_id_two)
  eq(child.b.diag_status, vim.NIL)
  type_keys([[\d]])
  eq(child.b.diag_status, 'disabled')

  child.api.nvim_set_current_buf(buf_id_one)
  eq(child.b.diag_status, 'disabled')
  type_keys([[\d]])
  eq(child.b.diag_status, 'enabled')

  child.api.nvim_set_current_buf(buf_id_two)
  eq(child.b.diag_status, 'disabled')
  type_keys([[\d]])
  eq(child.b.diag_status, 'enabled')
end

T['Mappings']['Toggle options']["does not disables 'hlsearch' directly"] = function()
  load_module()

  set_lines({ 'abc', 'abc' })

  eq(child.o.hlsearch, true)
  type_keys('/', 'a', '<CR>')
  eq(child.o.hlsearch, true)
  type_keys([[\h]])
  eq(child.o.hlsearch, true)
  eq(child.v.hlsearch, 0)

  -- Typing `n` should still show matches
  type_keys('n')
  eq(child.o.hlsearch, true)
  eq(child.v.hlsearch, 1)
end

T['Mappings']['Toggle options']['can be disabled'] = function()
  expect.match(child.cmd_capture([[nmap \w]]), 'No mapping')

  load_module({ mappings = { option_toggle_prefix = '' } })

  expect.match(child.cmd_capture([[nmap \w]]), 'No mapping')
end

T['Mappings']['Toggle options']['can work with `<Leader>`'] = function()
  vim.g.mapleader = ' '
  load_module({ mappings = { option_toggle_prefix = '<Leader>t' } })

  expect.match(child.cmd_capture([[nmap <Space>tw]]), 'wrap')
end

T['Mappings']['Windows'] = new_set()

T['Mappings']['Windows']['work for common navigation'] = function()
  local validate_cur_win = function(x) eq(child.api.nvim_get_current_win(), x) end

  load_module({ options = { basic = false }, mappings = { windows = true } })

  child.cmd('wincmd v | wincmd s | wincmd s')

  validate_cur_win(1003)
  type_keys('<C-l>')
  validate_cur_win(1000)
  type_keys('<C-h>')
  validate_cur_win(1003)
  type_keys('<C-j>')
  validate_cur_win(1002)
  type_keys('<C-k>')
  validate_cur_win(1003)

  -- Works with `[count]`
  type_keys('2<C-j>')
  validate_cur_win(1001)
end

T['Mappings']['Windows']['work for navigation in Terminal mode'] = function()
  load_module({ options = { basic = false }, mappings = { windows = true }, autocommands = { basic = false } })

  child.cmd('wincmd v')
  child.cmd('terminal')
  -- Wait for terminal to load
  vim.loop.sleep(100)
  child.cmd('startinsert')
  eq(child.fn.mode(), 't')

  eq(child.api.nvim_get_current_win(), 1001)
  type_keys('<C-w>l')
  eq(child.api.nvim_get_current_win(), 1000)
  eq(child.fn.mode(), 'n')
end

T['Mappings']['Windows']['work for resizing'] = function()
  local validate = function(dims) eq({ child.fn.winheight(0), child.fn.winwidth(0) }, dims) end

  load_module({ options = { basic = false }, mappings = { windows = true } })

  child.cmd('wincmd v | wincmd s')

  -- Should change correct dimension and respect `[count]`
  local start_height, start_width = child.fn.winheight(0), child.fn.winwidth(0)

  type_keys('<C-left>')
  validate({ start_height, start_width - 1 })
  type_keys('2<C-left>')
  validate({ start_height, start_width - 3 })

  type_keys('<C-right>')
  validate({ start_height, start_width - 2 })
  type_keys('2<C-right>')
  validate({ start_height, start_width })

  type_keys('<C-down>')
  validate({ start_height - 1, start_width })
  type_keys('2<C-down>')
  validate({ start_height - 3, start_width })

  type_keys('<C-up>')
  validate({ start_height - 2, start_width })
  type_keys('2<C-up>')
  validate({ start_height, start_width })
end

T['Mappings']['Move with alt'] = new_set()

T['Mappings']['Move with alt']['works in Insert mode'] = function()
  load_module({ mappings = { move_with_alt = true } })

  set_lines({ 'aaa', 'bbb' })
  set_cursor(1, 1)
  type_keys('a')

  eq(get_cursor(), { 1, 2 })
  type_keys('<M-h>')
  eq(get_cursor(), { 1, 1 })
  type_keys('<M-l>')
  eq(get_cursor(), { 1, 2 })
  type_keys('<M-j>')
  eq(get_cursor(), { 2, 2 })
  type_keys('<M-k>')
  eq(get_cursor(), { 1, 2 })
end

T['Mappings']['Move with alt']['works in Terminal mode'] = function()
  load_module({ mappings = { move_with_alt = true } })

  -- Too unstable to actually verify in Terminal mode
  expect.match(child.cmd_capture('tmap <M-h>'), '<Left>')
  expect.match(child.cmd_capture('tmap <M-j>'), '<Down>')
  expect.match(child.cmd_capture('tmap <M-k>'), '<Up>')
  expect.match(child.cmd_capture('tmap <M-l>'), '<Right>')
end

T['Mappings']['Move with alt']['works in Insert mode'] = function()
  load_module({ mappings = { move_with_alt = true } })

  type_keys(':hello')

  eq(child.fn.getcmdpos(), 6)
  type_keys('<M-h>')
  eq(child.fn.getcmdpos(), 5)
  type_keys('<M-l>')
  eq(child.fn.getcmdpos(), 6)
end

T['Autocommands'] = new_set()

T['Autocommands']['work'] = function()
  load_module()

  -- Highlight on yank
  child.lua('vim.highlight.on_yank = function() _G.been_here = true end')
  set_lines({ 'aaa' })
  type_keys('yiw')
  eq(child.lua_get('_G.been_here'), true)

  -- Start terminal in Insert mode
  child.cmd('terminal')
  eq(child.fn.mode(), 't')
end

T['Autocommands']['can be disabled'] = function()
  load_module({ autocommands = { basic = false } })
  child.cmd('terminal')
  eq(child.fn.mode(), 'n')
end

T['Autocommands']['respects `config.autocommands.relnum_in_visual_mode`'] = function()
  eq(child.o.relativenumber, false)
  type_keys('V')
  eq(child.o.relativenumber, false)
  type_keys('<C-v>')
  eq(child.o.relativenumber, false)
  type_keys('<Esc>')
  eq(child.o.relativenumber, false)

  -- Autocommand depends on `ModeChanged` event. It should load properly but
  -- not operate as expected.
  local has_modechanged = vim.fn.exists('##ModeChanged') == 1
  load_module({ autocommands = { relnum_in_visual_mode = true } })

  eq(child.o.relativenumber, false)
  type_keys('V')
  eq(child.o.relativenumber, has_modechanged)
  type_keys('<C-v>')
  eq(child.o.relativenumber, has_modechanged)
  type_keys('<Esc>')
  eq(child.o.relativenumber, false)
end

return T
