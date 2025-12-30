library(tidyverse)
library(readxl)

get_ywlz <- function(path) {
  target_cols <- c("审批编号", "审批状态", "审批结果",  
                   "发起人部门", "发起人姓名", 
                   "发起时间", "对方单位名称", "合作产品类型", "用印类型",
                   "审批记录(含处理人UserID)")
  sheets = excel_sheets(path)
  
  map(sheets, \(x) read_xlsx(path, sheet = x)) |> 
    list_rbind() |> 
    select(any_of(target_cols)) |> 
    arrange(发起时间) 
  
}

dt_ywlz = get_ywlz("data/业务流转流程（合同审批、用印、开户）-20250917154910.xlsx")

res_ycl <- dt_ywlz |>
  mutate(
    状态 = case_when(
      审批状态 == "完成" & 审批结果 == "同意" ~ "已归档",
      审批状态 == "审批中" &
        !str_detect(`审批记录(含处理人UserID)`, "行政合同归档") &
        str_detect(`审批记录(含处理人UserID)`, "用印审核|用印审批") ~ "已用印未归档",
      .default = NA_character_
    ),
    归档起始时间 = if_else(
      is.na(状态),
      NA_character_,
      str_extract(
        `审批记录(含处理人UserID)`,
        # 取最后一个时间：允许后面还有非数字字符，直到行尾
        "\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}(?=[^0-9]*$)"
      )
    ),
    用印主体 = str_extract(用印类型, "^[^-]+(?=-[^章]*章)|(?<=章-)[^-]+$")
  ) |> 
  select(-c(`审批记录(含处理人UserID)`), 用印主体) |> 
  writexl::write_xlsx("res.xlsx")

