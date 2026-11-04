-- boshiamy_commands.lua
-- 嘸蝦米指令表（共用模組，由 boshiamy_processor.lua、boshiamy_translator.lua require）
--
--   ,,T   進入繁體中文模式（預設）
--   ,,CT  打繁出簡：用繁體拆碼，經 OpenCC t2s 輸出簡體（simplifier）
--   ,,C   簡體模式：專案沒有嘸蝦米簡體字碼表，行為與 ,,CT 相同
--   ,,E   開關中英連打（候選列附上英文原文；選項 boshiamy_en_off，預設 false＝開啟）
--
-- 指令不分大小寫。注意小寫 ,,c 同時是「《」的嘸蝦米碼，所以小寫 ,,c 的指令提示
-- 會排在《之後（按空白仍出《，要點選提示才會切換）；大寫 ,,C 則直接是指令。

local M = {}

M.OPTION_SIMPLIFIED = "simplification"
-- 反向命名：RIME 選項預設為 false，所以「沒設定過」就是中英連打開啟，不需要 reset
M.OPTION_ENGLISH_OFF = "boshiamy_en_off"
M.CANDIDATE_TYPE = "boshiamy_cmd"
M.CANDIDATE_COMMENT = "〔指令〕"

local commands = {
  [",,t"] = {
    label = function(ctx) return "進入繁體中文模式" end,
    run = function(ctx) ctx:set_option(M.OPTION_SIMPLIFIED, false) end,
  },
  [",,ct"] = {
    label = function(ctx) return "進入打繁出簡模式" end,
    run = function(ctx) ctx:set_option(M.OPTION_SIMPLIFIED, true) end,
  },
  [",,c"] = {
    -- 沒有簡體字碼表，等同 ,,CT
    label = function(ctx) return "進入打繁出簡模式" end,
    run = function(ctx) ctx:set_option(M.OPTION_SIMPLIFIED, true) end,
  },
  [",,e"] = {
    label = function(ctx)
      if ctx:get_option(M.OPTION_ENGLISH_OFF) then return "開啟中英連打" end
      return "關閉中英連打"
    end,
    run = function(ctx) ctx:set_option(M.OPTION_ENGLISH_OFF, not ctx:get_option(M.OPTION_ENGLISH_OFF)) end,
  },
}

-- 依組字內容找指令，找不到回傳 nil
function M.lookup(input)
  if type(input) ~= "string" or input:sub(1, 2) ~= ",," then return nil end
  return commands[input:lower()]
end

-- 組字內容含大寫字母（真正的嘸蝦米指令寫法）
function M.is_explicit(input)
  return input:find("%u") ~= nil
end

-- 執行指令；成功回傳 true
function M.run(ctx, input)
  local cmd = M.lookup(input)
  if not cmd then return false end
  cmd.run(ctx)
  return true
end

return M
