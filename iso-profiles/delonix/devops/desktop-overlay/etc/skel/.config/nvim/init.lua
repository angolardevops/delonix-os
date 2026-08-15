-- DelonixOS — configuração mínima do Neovim.
--
-- Sem gestor de plugins e sem opinião a mais: isto é o editor de emergência
-- que tem de funcionar num bastion às 3 da manhã. Quem quiser LazyVim ou
-- AstroNvim instala por cima — nada aqui atrapalha.

vim.g.mapleader = " "

local o = vim.opt
o.number = true
o.relativenumber = true
o.signcolumn = "yes"
o.cursorline = true
o.termguicolors = true
o.mouse = "a"
o.clipboard = "unnamedplus"
o.undofile = true
o.swapfile = false
o.updatetime = 250
o.scrolloff = 6
o.ignorecase = true
o.smartcase = true
o.splitright = true
o.splitbelow = true
o.list = true
o.listchars = { tab = "→ ", trail = "·", nbsp = "␣" }

-- YAML e HCL não perdoam indentação errada: 2 espaços, sempre.
o.expandtab = true
o.shiftwidth = 4
o.tabstop = 4
vim.api.nvim_create_autocmd("FileType", {
    pattern = { "yaml", "yml", "json", "hcl", "terraform", "tf", "nix", "sh", "bash" },
    callback = function()
        vim.opt_local.shiftwidth = 2
        vim.opt_local.tabstop = 2
    end,
})

-- Manifestos de Kubernetes e Delonix são YAML mesmo quando a extensão mente.
vim.filetype.add({
    pattern = {
        [".*/manifests/.*%.ya?ml"] = "yaml",
        ["Delonixfile"] = "dockerfile",
        [".*%.tf"] = "terraform",
        [".*%.tfvars"] = "terraform",
    },
})

-- Cores da casa sobre o tema `habamax` (vem com o Neovim, não precisa de rede).
vim.cmd.colorscheme("habamax")
vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#e0202f", bold = true })
vim.api.nvim_set_hl(0, "Visual", { bg = "#8a0f18" })

-- Atalhos: só os que se usam todos os dias.
local map = vim.keymap.set
map("n", "<leader>w", "<cmd>write<cr>", { desc = "guardar" })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "sair" })
map("n", "<esc>", "<cmd>nohlsearch<cr>")
map("n", "<leader>e", "<cmd>Explore<cr>", { desc = "explorador de ficheiros" })
map("t", "<esc><esc>", "<C-\\><C-n>", { desc = "sair do modo terminal" })

-- Realce breve do que foi copiado — dá para ver o que se apanhou.
vim.api.nvim_create_autocmd("TextYankPost", {
    callback = function() vim.highlight.on_yank({ timeout = 150 }) end,
})
