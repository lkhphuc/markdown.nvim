local list = require('render-markdown.list')
local state = require('render-markdown.state')

local M = {}

M.namespace = vim.api.nvim_create_namespace('render-markdown.nvim')

M.clear = function()
    -- Remove existing highlights / virtual text
    vim.api.nvim_buf_clear_namespace(0, M.namespace, 0, -1)
end

M.refresh = function()
    if not state.enabled then
        return
    end
    if not vim.tbl_contains(state.config.file_types, vim.bo.filetype) then
        return
    end
    -- Needs to happen after file_type check and before mode check
    M.clear()
    if not vim.tbl_contains(state.config.render_modes, vim.fn.mode()) then
        return
    end

    vim.treesitter.get_parser():for_each_tree(function(tree, language_tree)
        local language = language_tree:lang()
        if language == 'markdown' then
            M.markdown(tree:root())
        elseif language == 'latex' then
            M.latex(tree:root())
        end
    end)
end

---@param root TSNode
M.markdown = function(root)
    local highlights = state.config.highlights
    ---@diagnostic disable-next-line: missing-parameter
    for id, node in state.markdown_query:iter_captures(root, 0) do
        local capture = state.markdown_query.captures[id]
        local value = vim.treesitter.get_node_text(node, 0)
        local start_row, start_col, end_row, end_col = node:range()

        if capture == 'heading' then
            local level = #value
            local heading = list.cycle(state.config.headings, level)
            local background = list.clamp_last(highlights.heading.backgrounds, level)
            local foreground = list.clamp_last(highlights.heading.foregrounds, level)

            local virt_text = { string.rep(' ', level - 1) .. heading, { foreground, background } }
            vim.api.nvim_buf_set_extmark(0, M.namespace, start_row, 0, {
                end_row = end_row + 1,
                end_col = 0,
                hl_group = background,
                virt_text = { virt_text },
                virt_text_pos = 'overlay',
                hl_eol = true,
            })
        elseif capture == 'code' then
            vim.api.nvim_buf_set_extmark(0, M.namespace, start_row, 0, {
                end_row = end_row,
                end_col = 0,
                hl_group = highlights.code,
                hl_eol = true,
            })
        elseif capture == 'list_marker' then
            -- List markers from tree-sitter should have leading spaces removed, however there are known
            -- edge cases in the parser: https://github.com/tree-sitter-grammars/tree-sitter-markdown/issues/127
            -- As a result we handle leading spaces here, can remove if this gets fixed upstream
            local _, leading_spaces = value:find('^%s*')
            local virt_text = { string.rep(' ', leading_spaces or 0) .. state.config.bullet, highlights.bullet }
            vim.api.nvim_buf_set_extmark(0, M.namespace, start_row, start_col, {
                end_row = end_row,
                end_col = end_col,
                virt_text = { virt_text },
                virt_text_pos = 'overlay',
            })
        elseif vim.tbl_contains({ 'table_head', 'table_delim', 'table_row' }, capture) then
            local row = value:gsub('|', '│')
            if capture == 'table_delim' then
                -- Order matters here, in particular handling inner intersections before left & right
                row = row:gsub('-', '─')
                    :gsub(' ', '─')
                    :gsub('─│─', '─┼─')
                    :gsub('│─', '├─')
                    :gsub('─│', '─┤')
            end

            local highlight = highlights.table.head
            if capture == 'table_row' then
                highlight = highlights.table.row
            end

            local virt_text = { row, highlight }
            vim.api.nvim_buf_set_extmark(0, M.namespace, start_row, start_col, {
                end_row = end_row,
                end_col = end_col,
                virt_text = { virt_text },
                virt_text_pos = 'overlay',
            })
        else
            -- Should only get here if user provides custom capture, currently unhandled
            vim.print('Unhandled capture: ' .. capture)
        end
    end
end

---@param root TSNode
M.latex = function(root)
    if vim.fn.executable('latex2text') ~= 1 then
        return
    end

    local latex = vim.treesitter.get_node_text(root, 0)
    local expression = vim.trim(vim.fn.system('latex2text', latex))
    local extra_space = vim.fn.strdisplaywidth(latex) - vim.fn.strdisplaywidth(expression)
    if extra_space < 0 then
        return
    end

    local start_row, start_col, end_row, end_col = root:range()
    local virt_text = { expression .. string.rep(' ', extra_space), state.config.highlights.latex }
    vim.api.nvim_buf_set_extmark(0, M.namespace, start_row, start_col, {
        end_row = end_row,
        end_col = end_col,
        virt_text = { virt_text },
        virt_text_pos = 'overlay',
    })
end

return M
