return {
    -- Need $OPENAI_API_KEY and added builling info to platform.openai
    {
        "jackMort/ChatGPT.nvim",
        config = function()
            require("chatgpt").setup()
        end,
        dependencies = {
            "MunifTanjim/nui.nvim",
            "nvim-lua/plenary.nvim",
            "folke/trouble.nvim",
            "nvim-telescope/telescope.nvim"
        }
    }
}
